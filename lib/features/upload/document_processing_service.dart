import 'dart:math' as math;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/annual_leave_allocation.dart';
import '../../core/models/document_type.dart';
import '../../core/models/duty.dart';
import '../../core/models/job_card.dart';
import '../../core/models/duty_type.dart';
import '../../core/models/parse_result.dart';
import '../../core/models/roster_source.dart';
import '../../core/parser/annual_leave_roster_parser.dart';
import '../../core/parser/base_roster_parser.dart';
import '../../core/parser/daily_amendment_parser.dart';
import '../../core/parser/job_card_parser.dart';
import '../smart_scan/smart_scan_engine.dart';
import '../smart_scan/smart_scan_result.dart';

class DocumentProcessingService {
  DocumentProcessingService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _documentTableName = 'roster_documents';
  static const String _dutyTableName = 'document_duties';
  static const String _annualLeaveAllocationTableName =
      'annual_leave_allocations';
  static const String _annualLeavePeriodTableName = 'annual_leave_periods';
  static const String _jobCardTableName = 'job_cards';

  static Future<DocumentProcessingResult> processUploadedDocument({
    required String documentId,
    required Uint8List bytes,
    required String originalFilename,
    required DocumentType documentType,
    DateTime? baseRosterCommencementDate,
    String? baseRosterSwapPartnerDriverNumber,
    bool baseRosterStartsWithPartner = false,
  }) async {
    final bool isBaseRoster = documentType == DocumentType.baseRoster;
    final bool isAnnualLeaveRoster =
        documentType == DocumentType.annualLeaveRoster;
    final bool isJobCard = documentType == DocumentType.jobCard;

    if (!isBaseRoster &&
        !isAnnualLeaveRoster &&
        !isJobCard &&
        !_isDailyAmendment(documentType)) {
      return const DocumentProcessingResult(
        status: DocumentProcessingStatus.pending,
        recordsInserted: 0,
        message:
            'This document type will be processed when its dedicated parser is connected.',
      );
    }

    if (!_isPdf(originalFilename) && !_isSupportedImage(originalFilename)) {
      throw const DocumentProcessingException(
        'Smart Scan cannot recognise this file format.',
      );
    }

    if (!SmartScanEngine.isSupported) {
      return const DocumentProcessingResult(
        status: DocumentProcessingStatus.pending,
        recordsInserted: 0,
        message:
            'The document was uploaded. Smart Scan will run on the native iPhone or Android app.',
      );
    }

    await _updateProcessingStatus(documentId, 'processing');

    try {
      final List<SmartScanResult> scanResults;

      if (_isPdf(originalFilename)) {
        scanResults = await SmartScanEngine.recognisePdf(
          bytes: bytes,
          fileName: originalFilename,
        );
      } else {
        scanResults = <SmartScanResult>[
          await SmartScanEngine.recogniseImage(
            bytes: bytes,
            fileName: originalFilename,
          ),
        ];
      }

      final List<String> reconstructedPageText = scanResults
          .map(_reconstructPageText)
          .where((String text) => text.trim().isNotEmpty)
          .toList(growable: false);

      if (reconstructedPageText.isEmpty) {
        throw const DocumentProcessingException(
          'No readable text was detected in the selected document.',
        );
      }

      final ParseResult parseResult;

      if (isBaseRoster) {
        final String? driverNumber = await _currentDriverNumber();

        if (driverNumber == null || driverNumber.trim().isEmpty) {
          throw const DocumentProcessingException(
            'Add your Base Roster driver number in Settings before processing this document.',
          );
        }

        if (baseRosterCommencementDate == null) {
          throw const DocumentProcessingException(
            'The Base Roster commencement Sunday is missing.',
          );
        }

        final BaseRosterParser parser = BaseRosterParser(
          commencementDate: baseRosterCommencementDate,
          driverNumber: driverNumber,
          swapPartnerDriverNumber: baseRosterSwapPartnerDriverNumber,
          initialLine: baseRosterStartsWithPartner
              ? BaseRosterInitialLine.swapPartner
              : BaseRosterInitialLine.driver,
        );

        parseResult = await parser.parse(pageText: reconstructedPageText);
      } else if (isAnnualLeaveRoster) {
        const AnnualLeaveRosterParser parser = AnnualLeaveRosterParser();

        parseResult = await parser.parse(pageText: reconstructedPageText);
      } else if (isJobCard) {
        const JobCardParser parser = JobCardParser();

        parseResult = await parser.parse(pageText: reconstructedPageText);
      } else {
        final DailyAmendmentParser parser = DailyAmendmentParser(
          documentType: documentType,
        );

        parseResult = await parser.parse(pageText: reconstructedPageText);
      }

      if (!parseResult.canImport) {
        throw DocumentProcessingException(_blockingWarningMessage(parseResult));
      }

      if (isJobCard) {
        final List<JobCard> cards = parseResult.jobCards;

        if (cards.isEmpty) {
          throw const DocumentProcessingException(
            'No complete Job Cards were detected.',
          );
        }

        final int insertedCards = await _replaceJobCards(
          documentId: documentId,
          cards: cards,
        );

        await _updateProcessingStatus(documentId, 'processed');

        return DocumentProcessingResult(
          status: DocumentProcessingStatus.processed,
          recordsInserted: insertedCards,
          message: '$insertedCards Job Cards were processed successfully.',
        );
      }

      if (isAnnualLeaveRoster) {
        final List<AnnualLeaveAllocation> allocations =
            parseResult.annualLeaveAllocations;

        if (allocations.isEmpty) {
          throw const DocumentProcessingException(
            'No Annual Leave driver allocations were detected.',
          );
        }

        await _replaceAnnualLeaveAllocations(
          documentId: documentId,
          allocations: allocations,
        );

        await _updateProcessingStatus(documentId, 'processed');

        return DocumentProcessingResult(
          status: DocumentProcessingStatus.processed,
          recordsInserted: allocations.length,
          message:
              '${allocations.length} Annual Leave allocations were processed successfully.',
        );
      }

      final List<Duty> importableDuties = parseResult.duties
          .where((duty) => duty.hasDriverIdentity)
          .toList(growable: false);

      if (importableDuties.isEmpty) {
        throw DocumentProcessingException(
          isBaseRoster
              ? 'No Base Roster duties matching your driver number were detected.'
              : 'No duties with a payroll number or roster code were detected.',
        );
      }

      await _replaceDocumentDuties(
        documentId: documentId,
        duties: importableDuties,
      );

      await _updateProcessingStatus(documentId, 'processed');

      return DocumentProcessingResult(
        status: DocumentProcessingStatus.processed,
        recordsInserted: importableDuties.length,
        message:
            '${importableDuties.length} duty records were processed successfully.',
      );
    } catch (error) {
      try {
        await _updateProcessingStatus(documentId, 'failed');
      } catch (_) {
        // Preserve the original processing error.
      }

      if (error is DocumentProcessingException) {
        rethrow;
      }

      if (error is SmartScanException) {
        throw DocumentProcessingException(error.message);
      }

      if (error is PostgrestException) {
        throw DocumentProcessingException(error.message);
      }

      throw const DocumentProcessingException(
        'Roster Buddy could not process this document.',
      );
    }
  }

  static Future<String?> _currentDriverNumber() async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const DocumentProcessingException(
        'You must be signed in before processing a Base Roster.',
      );
    }

    final Map<String, dynamic>? profile = await _supabase
        .from('driver_profiles')
        .select('driver_number')
        .eq('user_id', user.id)
        .maybeSingle();

    final String tableDriverNumber = (profile?['driver_number'] ?? '')
        .toString()
        .trim();

    if (tableDriverNumber.isNotEmpty) {
      return tableDriverNumber;
    }

    final String metadataDriverNumber =
        (user.userMetadata?['driver_number'] ?? '').toString().trim();

    return metadataDriverNumber.isEmpty ? null : metadataDriverNumber;
  }

  static Future<void> _replaceAnnualLeaveAllocations({
    required String documentId,
    required List<AnnualLeaveAllocation> allocations,
  }) async {
    await _supabase
        .from(_annualLeaveAllocationTableName)
        .delete()
        .eq('document_id', documentId);

    for (final AnnualLeaveAllocation allocation in allocations) {
      final Map<String, dynamic> insertedAllocation = await _supabase
          .from(_annualLeaveAllocationTableName)
          .insert({
            'document_id': documentId,
            'leave_year': allocation.leaveYear,
            'depot': allocation.depot.trim(),
            'driver_number': allocation.driverNumber.trim(),
            'surname': allocation.surname.trim(),
            'block_number': allocation.blockNumber,
            'source': _databaseAnnualLeaveSource(allocation.source),
            'original_block_number': allocation.originalBlockNumber,
            'other_driver_number': _cleanValue(allocation.otherDriverNumber),
            'other_driver_surname': _cleanValue(allocation.otherDriverSurname),
            'swap_reference': _cleanValue(allocation.swapReference),
            'is_confirmed': allocation.isConfirmed,
            'page_number': allocation.pageNumber,
            'unique_key': allocation.uniqueKey,
          })
          .select('id')
          .single();

      final String allocationId = insertedAllocation['id'].toString();

      if (allocation.periods.isEmpty) {
        continue;
      }

      final List<Map<String, dynamic>> periodRows = allocation.periods
          .map(
            (AnnualLeavePeriod period) => {
              'allocation_id': allocationId,
              'period_type': _databaseAnnualLeavePeriodType(period.type),
              'start_date': _databaseDate(period.startDate),
              'end_date': _databaseDate(period.endDate),
            },
          )
          .toList(growable: false);

      await _supabase.from(_annualLeavePeriodTableName).insert(periodRows);
    }
  }

  static String _databaseAnnualLeaveSource(AnnualLeaveAllocationSource source) {
    switch (source) {
      case AnnualLeaveAllocationSource.officialRoster:
        return 'official_roster';
      case AnnualLeaveAllocationSource.agreedMove:
        return 'agreed_move';
      case AnnualLeaveAllocationSource.mutualSwap:
        return 'mutual_swap';
      case AnnualLeaveAllocationSource.manualCorrection:
        return 'manual_correction';
    }
  }

  static String _databaseAnnualLeavePeriodType(AnnualLeavePeriodType type) {
    switch (type) {
      case AnnualLeavePeriodType.spring:
        return 'spring';
      case AnnualLeavePeriodType.summerFirstWeek:
        return 'summer_first_week';
      case AnnualLeavePeriodType.summerSecondWeek:
        return 'summer_second_week';
      case AnnualLeavePeriodType.winter:
        return 'winter';
    }
  }

  static Future<int> _replaceJobCards({
    required String documentId,
    required List<JobCard> cards,
  }) async {
    final Map<String, JobCard> uniqueCards = <String, JobCard>{};

    for (final JobCard card in cards) {
      uniqueCards.putIfAbsent(card.uniqueKey, () => card);
    }

    final List<JobCard> cardsToInsert = uniqueCards.values.toList(
      growable: false,
    );

    await _supabase
        .from(_jobCardTableName)
        .delete()
        .eq('document_id', documentId);

    if (cardsToInsert.isEmpty) {
      return 0;
    }

    const int batchSize = 250;

    for (int start = 0; start < cardsToInsert.length; start += batchSize) {
      final int end = math.min(start + batchSize, cardsToInsert.length);

      final List<Map<String, dynamic>> rows = cardsToInsert
          .sublist(start, end)
          .map(
            (JobCard card) => <String, dynamic>{
              'document_id': documentId,
              'turn_number': card.turnNumber.trim(),
              'original_turn_code': card.originalTurnCode.trim(),
              'day_code': card.dayCode.trim(),
              'plan_type': card.planType.name,
              'valid_from': _databaseDate(card.validFrom),
              'valid_to': _databaseDate(card.validTo),
              'book_on': _databaseTime(card.bookOn),
              'book_off': _databaseTime(card.bookOff),
              'rostered_minutes': card.rosteredMinutes,
              'page_number': card.pageNumber,
              'raw_text': _cleanValue(card.rawText),
              'instructions': card.instructions,
              'unique_key': card.uniqueKey,
            },
          )
          .toList(growable: false);

      await _supabase.from(_jobCardTableName).insert(rows);
    }

    return cardsToInsert.length;
  }

  static Future<void> _replaceDocumentDuties({
    required String documentId,
    required List<Duty> duties,
  }) async {
    await _supabase.from(_dutyTableName).delete().eq('document_id', documentId);

    const int batchSize = 250;

    for (var start = 0; start < duties.length; start += batchSize) {
      final int end = math.min(start + batchSize, duties.length);

      final List<Map<String, dynamic>> rows = duties
          .sublist(start, end)
          .map((duty) => _dutyRow(documentId: documentId, duty: duty))
          .toList(growable: false);

      await _supabase.from(_dutyTableName).insert(rows);
    }
  }

  static Map<String, dynamic> _dutyRow({
    required String documentId,
    required Duty duty,
  }) {
    return {
      'document_id': documentId,
      'duty_date': _databaseDate(duty.date),
      'source': _databaseRosterSource(duty.source),
      'duty_type': _databaseDutyType(duty.dutyType),
      'turn_number': _cleanValue(duty.turnNumber),
      'book_on': _databaseTime(duty.bookOn),
      'book_off': _databaseTime(duty.bookOff),
      'rostered_minutes': duty.rosteredMinutes,
      'remarks': _cleanValue(duty.remarks),
      'driver_number': _cleanValue(duty.driverNumber),
      'payroll_number': _cleanValue(duty.payrollNumber),
      'driver_name': _cleanValue(duty.driverName),
      'depot': _cleanValue(duty.depot),
      'amendment_code': _cleanValue(duty.amendmentCode),
      'mileage': _cleanValue(duty.mileage),
      'page_number': duty.pageNumber,
      'raw_text': _cleanValue(duty.rawText),
      'unique_key': duty.uniqueKey,
    };
  }

  static Future<void> _updateProcessingStatus(
    String documentId,
    String status,
  ) async {
    await _supabase
        .from(_documentTableName)
        .update({'processing_status': status})
        .eq('id', documentId);
  }

  static String _reconstructPageText(SmartScanResult result) {
    if (result.lines.isEmpty) {
      return result.fullText;
    }

    final List<SmartScanTextLine> sortedLines =
        List<SmartScanTextLine>.from(result.lines)..sort((first, second) {
          final int topComparison = first.top.compareTo(second.top);

          if (topComparison != 0) {
            return topComparison;
          }

          return first.left.compareTo(second.left);
        });

    final List<List<SmartScanTextLine>> rows = [];

    for (final SmartScanTextLine line in sortedLines) {
      if (line.text.trim().isEmpty) {
        continue;
      }

      if (rows.isEmpty) {
        rows.add([line]);
        continue;
      }

      final List<SmartScanTextLine> currentRow = rows.last;
      final double currentTop =
          currentRow.map((item) => item.top).reduce((a, b) => a + b) /
          currentRow.length;

      final double lineHeight = math.max(1, line.bottom - line.top);
      final double tolerance = math.max(10, lineHeight * 0.65);

      if ((line.top - currentTop).abs() <= tolerance) {
        currentRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    final List<String> reconstructedRows = [];

    for (final List<SmartScanTextLine> row in rows) {
      row.sort((first, second) => first.left.compareTo(second.left));

      final String rowText = row
          .map((line) => line.text.trim())
          .where((text) => text.isNotEmpty)
          .join('  ');

      if (rowText.isNotEmpty) {
        reconstructedRows.add(rowText);
      }
    }

    if (reconstructedRows.isEmpty) {
      return result.fullText;
    }

    return reconstructedRows.join('\n');
  }

  static String _blockingWarningMessage(ParseResult result) {
    final blockingMessages = result.warnings
        .where((warning) => warning.preventsImport)
        .map((warning) => warning.message.trim())
        .where((message) => message.isNotEmpty)
        .toList(growable: false);

    if (blockingMessages.isNotEmpty) {
      return blockingMessages.join(' ');
    }

    return 'No usable duty records were detected in this document.';
  }

  static bool _isDailyAmendment(DocumentType type) {
    return type == DocumentType.tenDayAmendment ||
        type == DocumentType.sevenDayAmendment ||
        type == DocumentType.fortyEightHourAmendment;
  }

  static bool _isPdf(String filename) {
    return filename.toLowerCase().trim().endsWith('.pdf');
  }

  static bool _isSupportedImage(String filename) {
    final String lower = filename.toLowerCase().trim();

    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  static String _databaseDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String? _databaseTime(String? value) {
    final String? cleaned = _cleanValue(value);

    if (cleaned == null) {
      return null;
    }

    return cleaned.length == 5 ? '$cleaned:00' : cleaned;
  }

  static String _databaseRosterSource(RosterSource source) {
    switch (source) {
      case RosterSource.baseRoster:
        return 'base_roster';
      case RosterSource.tenDay:
        return '10_day';
      case RosterSource.sevenDay:
        return '7_day';
      case RosterSource.fortyEightHour:
        return '48_hour';
      case RosterSource.annualLeave:
        throw const DocumentProcessingException(
          'Annual Leave allocations are stored separately from document duties.',
        );
      case RosterSource.manual:
        throw const DocumentProcessingException(
          'Manual duties cannot be stored as parsed document duties.',
        );
    }
  }

  static String _databaseDutyType(DutyType dutyType) {
    switch (dutyType) {
      case DutyType.working:
        return 'working';
      case DutyType.training:
        return 'training';
      case DutyType.medical:
        return 'medical';
      case DutyType.restDay:
        return 'rest_day';
      case DutyType.annualLeave:
        return 'annual_leave';
      case DutyType.sick:
        return 'sick';
      case DutyType.publicHoliday:
        return 'public_holiday';
      case DutyType.unavailable:
        return 'unavailable';
      case DutyType.unknown:
        return 'unknown';
    }
  }

  static String? _cleanValue(String? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.trim();

    return cleaned.isEmpty ? null : cleaned;
  }
}

enum DocumentProcessingStatus { processed, pending }

class DocumentProcessingResult {
  const DocumentProcessingResult({
    required this.status,
    required this.recordsInserted,
    required this.message,
  });

  final DocumentProcessingStatus status;
  final int recordsInserted;
  final String message;

  bool get wasProcessed => status == DocumentProcessingStatus.processed;
}

class DocumentProcessingException implements Exception {
  const DocumentProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}
