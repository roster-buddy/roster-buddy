import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'storage_service.dart';

enum UploadSource { camera, photoLibrary, file }

class PickedUpload {
  const PickedUpload({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;

  String get filename => fileName;
}

class UploadService {
  UploadService._();

  static final ImagePicker _imagePicker = ImagePicker();
  static bool _uploadInProgress = false;

  static Future<PickedUpload?> pickDocument(
    Object firstArgument, [
    UploadSource? secondArgument,
  ]) async {
    BuildContext? context;
    late final UploadSource source;

    if (firstArgument is BuildContext && secondArgument != null) {
      context = firstArgument;
      source = secondArgument;
    } else if (firstArgument is UploadSource) {
      source = firstArgument;
    } else {
      throw ArgumentError('Invalid upload arguments.');
    }

    final PickedUpload? selectedUpload = await _selectDocument(source);

    if (selectedUpload == null) {
      return null;
    }

    if (context != null && context.mounted) {
      await uploadPickedDocument(
        context,
        selectedUpload,
        detectedType: 'Unclassified',
        manuallyLabelled: false,
      );
    }

    return selectedUpload;
  }

  static Future<bool> uploadPickedDocument(
    BuildContext context,
    PickedUpload upload, {
    required String detectedType,
    required bool manuallyLabelled,
    BaseRosterActivation? baseRosterActivation,
  }) async {
    if (_uploadInProgress) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('A document is already being uploaded.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return false;
    }

    _uploadInProgress = true;
    _showUploadingDialog(context, upload.fileName);

    try {
      final UploadRosterResult result =
          await StorageService.uploadRosterDocument(
            bytes: upload.bytes,
            originalFilename: upload.fileName,
            detectedType: detectedType,
            manuallyLabelled: manuallyLabelled,
            baseRosterActivation: baseRosterActivation,
          );

      if (!context.mounted) {
        return true;
      }

      _closeUploadingDialog(context);

      await _showUploadResult(
        context,
        documentType: detectedType,
        outcome: _displayOutcome(result.outcome),
        message: result.message,
        recordsInserted: result.recordsInserted,
      );

      return true;
    } catch (error) {
      if (!context.mounted) {
        return false;
      }

      _closeUploadingDialog(context);

      final String errorMessage = error is StorageServiceException
          ? error.message
          : 'The document could not be uploaded. Please try again.';

      await _showUploadResult(
        context,
        documentType: detectedType,
        outcome: UploadDisplayOutcome.uploadFailed,
        message: errorMessage,
        recordsInserted: 0,
      );

      return false;
    } finally {
      _uploadInProgress = false;
    }
  }

  static UploadDisplayOutcome _displayOutcome(UploadProcessingOutcome outcome) {
    switch (outcome) {
      case UploadProcessingOutcome.processed:
        return UploadDisplayOutcome.processed;
      case UploadProcessingOutcome.pending:
        return UploadDisplayOutcome.pending;
      case UploadProcessingOutcome.failed:
        return UploadDisplayOutcome.processingFailed;
    }
  }

  static Future<PickedUpload?> _selectDocument(UploadSource source) async {
    switch (source) {
      case UploadSource.camera:
        return _pickCameraImage();
      case UploadSource.photoLibrary:
        return _pickPhotoLibraryImages();
      case UploadSource.file:
        return _pickFiles();
    }
  }

  static Future<PickedUpload?> _pickCameraImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );

    if (image == null) {
      return null;
    }

    final Uint8List bytes = await image.readAsBytes();

    return PickedUpload(
      bytes: bytes,
      fileName: _filenameFromPath(
        image.name.isNotEmpty ? image.name : image.path,
      ),
    );
  }

  static Future<PickedUpload?> _pickPhotoLibraryImages() async {
    final List<XFile> images = await _imagePicker.pickMultiImage(
      imageQuality: 100,
    );

    if (images.isEmpty) {
      return null;
    }

    if (images.length == 1) {
      final XFile image = images.single;

      return PickedUpload(
        bytes: await image.readAsBytes(),
        fileName: _filenameFromPath(
          image.name.isNotEmpty ? image.name : image.path,
        ),
      );
    }

    final List<Uint8List> imageBytes = [];

    for (final XFile image in images) {
      imageBytes.add(await image.readAsBytes());
    }

    return PickedUpload(
      bytes: await _createMultiPagePdf(imageBytes),
      fileName: _multiPageFilename(),
    );
  }

  static Future<PickedUpload?> _pickFiles() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    if (result.files.length == 1) {
      final PlatformFile selectedFile = result.files.single;
      final Uint8List? bytes = selectedFile.bytes;

      if (bytes == null) {
        throw StateError('The selected file could not be read.');
      }

      return PickedUpload(bytes: bytes, fileName: selectedFile.name);
    }

    final bool containsPdf = result.files.any(
      (file) => file.extension?.toLowerCase() == 'pdf',
    );

    if (containsPdf) {
      throw StateError(
        'Choose one PDF, or select multiple image files without a PDF.',
      );
    }

    final List<Uint8List> imageBytes = [];

    for (final PlatformFile file in result.files) {
      final Uint8List? bytes = file.bytes;

      if (bytes == null) {
        throw StateError('${file.name} could not be read.');
      }

      imageBytes.add(bytes);
    }

    return PickedUpload(
      bytes: await _createMultiPagePdf(imageBytes),
      fileName: _multiPageFilename(),
    );
  }

  static Future<Uint8List> _createMultiPagePdf(
    List<Uint8List> imageBytes,
  ) async {
    if (imageBytes.isEmpty) {
      throw StateError('No document pages were selected.');
    }

    final pw.Document document = pw.Document();

    for (final Uint8List bytes in imageBytes) {
      final pw.MemoryImage image;

      try {
        image = pw.MemoryImage(bytes);
      } catch (_) {
        throw StateError(
          'One of the selected images could not be added to the document.',
        );
      }

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (context) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );
    }

    return document.save();
  }

  static String _multiPageFilename() {
    final DateTime now = DateTime.now();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    final String timestamp =
        '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}-'
        '${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}';

    return 'roster-pages-$timestamp.pdf';
  }

  static String _filenameFromPath(String path) {
    final String normalisedPath = path.replaceAll('\\', '/');
    final String filename = normalisedPath.split('/').last.trim();

    return filename.isEmpty ? 'roster-image.jpg' : filename;
  }

  static void _showUploadingDialog(BuildContext context, String filename) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Uploading and processing'),
            content: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(filename, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _closeUploadingDialog(BuildContext context) {
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);

    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  static Future<void> _showUploadResult(
    BuildContext context, {
    required String documentType,
    required UploadDisplayOutcome outcome,
    required String message,
    required int recordsInserted,
  }) async {
    final bool staysLonger =
        outcome == UploadDisplayOutcome.processingFailed ||
        outcome == UploadDisplayOutcome.uploadFailed;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: _outcomeTitle(outcome),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        Future<void>.delayed(
          Duration(milliseconds: staysLonger ? 4200 : 2600),
          () {
            if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          },
        );

        return _UploadResultCard(
          documentType: documentType,
          outcome: outcome,
          message: message,
          recordsInserted: recordsInserted,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final CurvedAnimation curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );

        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.65, end: 1).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  static String _outcomeTitle(UploadDisplayOutcome outcome) {
    switch (outcome) {
      case UploadDisplayOutcome.processed:
        return 'Document processed';
      case UploadDisplayOutcome.pending:
        return 'Document uploaded';
      case UploadDisplayOutcome.processingFailed:
        return 'Processing needs attention';
      case UploadDisplayOutcome.uploadFailed:
        return 'Upload unsuccessful';
    }
  }
}

enum UploadDisplayOutcome { processed, pending, processingFailed, uploadFailed }

class _UploadResultCard extends StatefulWidget {
  const _UploadResultCard({
    required this.documentType,
    required this.outcome,
    required this.message,
    required this.recordsInserted,
  });

  final String documentType;
  final UploadDisplayOutcome outcome;
  final String message;
  final int recordsInserted;

  @override
  State<_UploadResultCard> createState() => _UploadResultCardState();
}

class _UploadResultCardState extends State<_UploadResultCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _iconScale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _resultColour {
    switch (widget.outcome) {
      case UploadDisplayOutcome.processed:
        return const Color(0xFF2E7D32);
      case UploadDisplayOutcome.pending:
        return const Color(0xFF1769AA);
      case UploadDisplayOutcome.processingFailed:
        return const Color(0xFFF59E0B);
      case UploadDisplayOutcome.uploadFailed:
        return const Color(0xFFC62828);
    }
  }

  Color get _backgroundColour {
    switch (widget.outcome) {
      case UploadDisplayOutcome.processed:
        return const Color(0xFFE7F6EA);
      case UploadDisplayOutcome.pending:
        return const Color(0xFFE8F2FA);
      case UploadDisplayOutcome.processingFailed:
        return const Color(0xFFFFF4D6);
      case UploadDisplayOutcome.uploadFailed:
        return const Color(0xFFFDECEC);
    }
  }

  IconData get _icon {
    switch (widget.outcome) {
      case UploadDisplayOutcome.processed:
        return Icons.check_rounded;
      case UploadDisplayOutcome.pending:
        return Icons.cloud_done_outlined;
      case UploadDisplayOutcome.processingFailed:
        return Icons.warning_amber_rounded;
      case UploadDisplayOutcome.uploadFailed:
        return Icons.close_rounded;
    }
  }

  String get _statusText {
    switch (widget.outcome) {
      case UploadDisplayOutcome.processed:
        return widget.recordsInserted == 1
            ? '1 duty processed'
            : '${widget.recordsInserted} duties processed';
      case UploadDisplayOutcome.pending:
        return 'Uploaded successfully';
      case UploadDisplayOutcome.processingFailed:
        return 'Uploaded — processing needs attention';
      case UploadDisplayOutcome.uploadFailed:
        return 'Upload unsuccessful';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: 370,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                blurRadius: 28,
                spreadRadius: 2,
                color: Color(0x33000000),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _iconScale,
                child: Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    color: _backgroundColour,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, color: _resultColour, size: 66),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.documentType,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF102A43),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _resultColour,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF52667A),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
