import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/services/job_card_service.dart';
import '../../core/services/pdf_page_renderer.dart'
    if (dart.library.js_interop) '../../core/services/pdf_page_renderer_web.dart';

Future<void> openJobCardViewer(
  BuildContext context,
  JobCardService service,
  JobCardMatch match,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _JobCardViewer(service: service, match: match),
    ),
  );
}

class _JobCardViewer extends StatefulWidget {
  const _JobCardViewer({required this.service, required this.match});

  final JobCardService service;
  final JobCardMatch match;

  @override
  State<_JobCardViewer> createState() => _JobCardViewerState();
}

class _JobCardViewerState extends State<_JobCardViewer> {
  late Future<Uint8List> _image = _loadPage();

  Future<Uint8List> _loadPage() async {
    final bytes = await widget.service.downloadJobCard(widget.match);
    if (!widget.match.originalFilename.toLowerCase().endsWith('.pdf')) {
      return bytes;
    }

    final page = widget.match.jobCard.pageNumber ?? 1;
    return const PdfPageRenderer().renderPage(bytes, page > 0 ? page : 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Job card · ${widget.match.jobCard.originalTurnCode}'),
      ),
      body: FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not open this job card.'),
                  TextButton(
                    onPressed: () => setState(() => _image = _loadPage()),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          return InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.memory(snapshot.requireData, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}
