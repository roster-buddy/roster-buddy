import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/document_type.dart';
import 'document_processing_service.dart';

enum BaseRosterStartingLine { mine, partner }

class BaseRosterActivation {
  const BaseRosterActivation({
    required this.commencementDate,
    required this.hasMutualSwap,
    required this.startingLine,
    this.swapPartnerDriverNumber,
  });

  final DateTime commencementDate;
  final bool hasMutualSwap;
  final String? swapPartnerDriverNumber;
  final BaseRosterStartingLine startingLine;
}

enum UploadProcessingOutcome { processed, pending, failed }

class UploadRosterResult {
  const UploadRosterResult({
    required this.documentId,
    required this.outcome,
    required this.recordsInserted,
    required this.message,
  });

  final String documentId;
  final UploadProcessingOutcome outcome;
  final int recordsInserted;
  final String message;

  bool get wasProcessed => outcome == UploadProcessingOutcome.processed;

  bool get isPending => outcome == UploadProcessingOutcome.pending;

  bool get processingFailed => outcome == UploadProcessingOutcome.failed;
}

class StorageService {
  StorageService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _bucketName = 'roster-documents';
  static const String _documentTableName = 'roster_documents';
  static const String _baseRosterTableName = 'base_rosters';

  static Future<UploadRosterResult> uploadRosterDocument({
    required Uint8List bytes,
    required String originalFilename,
    required String detectedType,
    required bool manuallyLabelled,
    BaseRosterActivation? baseRosterActivation,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const StorageServiceException(
        'You must be signed in before uploading a document.',
      );
    }

    if (bytes.isEmpty) {
      throw const StorageServiceException('The selected document is empty.');
    }

    final DocumentType documentType = _documentType(detectedType);
    final String databaseDocumentType = _databaseDocumentType(documentType);

    _validateBaseRosterActivation(
      documentType: documentType,
      activation: baseRosterActivation,
    );

    final String safeFilename = _sanitiseFilename(originalFilename);
    final int timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final String storagePath = '${user.id}/$timestamp-$safeFilename';

    bool storageUploadCompleted = false;
    String? documentId;

    try {
      await _supabase.storage
          .from(_bucketName)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: false),
          );

      storageUploadCompleted = true;

      final Map<String, dynamic> documentRow = await _supabase
          .from(_documentTableName)
          .insert({
            'user_id': user.id,
            'storage_path': storagePath,
            'original_filename': originalFilename,
            'file_size_bytes': bytes.length,
            'detected_type': databaseDocumentType,
            'detection_confidence': manuallyLabelled ? null : 1.0,
            'manually_labelled': manuallyLabelled,
            'processing_status': 'uploaded',
          })
          .select('id')
          .single();

      documentId = documentRow['id'].toString();

      if (baseRosterActivation != null) {
        await _insertBaseRosterActivation(
          userId: user.id,
          documentId: documentId,
          activation: baseRosterActivation,
        );
      }
    } catch (error) {
      await _removeIncompleteUpload(
        documentId: documentId,
        storageUploadCompleted: storageUploadCompleted,
        storagePath: storagePath,
      );

      throw StorageServiceException(_friendlyUploadErrorMessage(error));
    }

    final String completedDocumentId = documentId;

    try {
      final DocumentProcessingResult processingResult =
          await DocumentProcessingService.processUploadedDocument(
            documentId: completedDocumentId,
            bytes: bytes,
            originalFilename: originalFilename,
            documentType: documentType,
            baseRosterCommencementDate: baseRosterActivation?.commencementDate,
            baseRosterSwapPartnerDriverNumber:
                baseRosterActivation?.hasMutualSwap == true
                ? baseRosterActivation?.swapPartnerDriverNumber
                : null,
            baseRosterStartsWithPartner:
                baseRosterActivation?.startingLine ==
                BaseRosterStartingLine.partner,
          );

      switch (processingResult.status) {
        case DocumentProcessingStatus.processed:
          return UploadRosterResult(
            documentId: completedDocumentId,
            outcome: UploadProcessingOutcome.processed,
            recordsInserted: processingResult.recordsInserted,
            message: processingResult.message,
          );

        case DocumentProcessingStatus.pending:
          return UploadRosterResult(
            documentId: completedDocumentId,
            outcome: UploadProcessingOutcome.pending,
            recordsInserted: processingResult.recordsInserted,
            message: processingResult.message,
          );
      }
    } on DocumentProcessingException catch (error) {
      return UploadRosterResult(
        documentId: completedDocumentId,
        outcome: UploadProcessingOutcome.failed,
        recordsInserted: 0,
        message: error.message,
      );
    } catch (error) {
      return UploadRosterResult(
        documentId: completedDocumentId,
        outcome: UploadProcessingOutcome.failed,
        recordsInserted: 0,
        message: _friendlyProcessingErrorMessage(error),
      );
    }
  }

  static void _validateBaseRosterActivation({
    required DocumentType documentType,
    required BaseRosterActivation? activation,
  }) {
    if (documentType == DocumentType.baseRoster && activation == null) {
      throw const StorageServiceException(
        'The Base Roster commencement details are missing.',
      );
    }

    if (documentType != DocumentType.baseRoster && activation != null) {
      throw const StorageServiceException(
        'Base Roster activation details were supplied for the wrong '
        'document type.',
      );
    }

    if (activation != null &&
        activation.commencementDate.weekday != DateTime.sunday) {
      throw const StorageServiceException(
        'A Base Roster must commence on a Sunday.',
      );
    }

    if (activation != null &&
        activation.hasMutualSwap &&
        (activation.swapPartnerDriverNumber == null ||
            activation.swapPartnerDriverNumber!.trim().isEmpty)) {
      throw const StorageServiceException(
        'Enter the mutual swap partner roster code.',
      );
    }
  }

  static Future<void> _insertBaseRosterActivation({
    required String userId,
    required String documentId,
    required BaseRosterActivation activation,
  }) async {
    await _supabase.from(_baseRosterTableName).insert({
      'user_id': userId,
      'document_id': documentId,
      'commencement_date': _databaseDate(activation.commencementDate),
      'has_mutual_swap': activation.hasMutualSwap,
      'swap_partner_driver_number': activation.hasMutualSwap
          ? activation.swapPartnerDriverNumber?.trim()
          : null,
      'starts_with_line':
          activation.startingLine == BaseRosterStartingLine.partner
          ? 'partner'
          : 'mine',
    });
  }

  static Future<void> _removeIncompleteUpload({
    required String? documentId,
    required bool storageUploadCompleted,
    required String storagePath,
  }) async {
    if (documentId != null) {
      try {
        await _supabase.from(_documentTableName).delete().eq('id', documentId);
      } catch (_) {
        // Preserve the original upload error.
      }
    }

    if (storageUploadCompleted) {
      try {
        await _supabase.storage.from(_bucketName).remove([storagePath]);
      } catch (_) {
        // Preserve the original upload error.
      }
    }
  }

  static DocumentType _documentType(String detectedType) {
    switch (detectedType.trim()) {
      case 'Base Roster':
        return DocumentType.baseRoster;
      case '10-Day Amendment':
        return DocumentType.tenDayAmendment;
      case '7-Day Amendment':
        return DocumentType.sevenDayAmendment;
      case '48-Hour Amendment':
        return DocumentType.fortyEightHourAmendment;
      case 'Annual Leave Roster':
        return DocumentType.annualLeaveRoster;
      case 'Job Card':
        return DocumentType.jobCard;
      default:
        throw const StorageServiceException(
          'The selected document type is not supported.',
        );
    }
  }

  static String _databaseDocumentType(DocumentType type) {
    switch (type) {
      case DocumentType.baseRoster:
        return 'base_roster';
      case DocumentType.tenDayAmendment:
        return '10_day_amendment';
      case DocumentType.sevenDayAmendment:
        return '7_day_amendment';
      case DocumentType.fortyEightHourAmendment:
        return '48_hour_amendment';
      case DocumentType.annualLeaveRoster:
        return 'annual_leave_roster';
      case DocumentType.jobCard:
        return 'job_card';
      case DocumentType.unknown:
        throw const StorageServiceException(
          'The selected document type is not supported.',
        );
    }
  }

  static String _databaseDate(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String _sanitiseFilename(String filename) {
    final String trimmed = filename.trim().isEmpty
        ? 'roster-document'
        : filename.trim();

    return trimmed
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  static String _friendlyUploadErrorMessage(Object error) {
    if (error is StorageServiceException) {
      return error.message;
    }

    if (error is StorageException) {
      return error.message;
    }

    if (error is PostgrestException) {
      return error.message;
    }

    return 'The document could not be uploaded. Please try again.';
  }

  static String _friendlyProcessingErrorMessage(Object error) {
    if (error is StorageServiceException) {
      return error.message;
    }

    if (error is StorageException) {
      return error.message;
    }

    if (error is PostgrestException) {
      return error.message;
    }

    return 'Roster Buddy could not process the document.';
  }
}

class StorageServiceException implements Exception {
  const StorageServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
