import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'smart_scan_engine.dart';
import 'smart_scan_result.dart';

class SmartScanDebugPage extends StatefulWidget {
  const SmartScanDebugPage({
    required this.bytes,
    required this.fileName,
    required this.documentType,
    super.key,
  });

  final Uint8List bytes;
  final String fileName;
  final String documentType;

  @override
  State<SmartScanDebugPage> createState() => _SmartScanDebugPageState();
}

class _SmartScanDebugPageState extends State<SmartScanDebugPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color textGrey = Color(0xFF52667A);

  SmartScanResult? _result;
  String? _message;
  bool _isReading = true;

  bool get _isPdf => widget.fileName.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    _runSmartScan();
  }

  Future<void> _runSmartScan() async {
    if (_isPdf) {
      setState(() {
        _isReading = false;
        _message =
            'PDF text recognition will be added in the next stage. '
            'PDF pages must first be converted into images.';
      });
      return;
    }

    if (!SmartScanEngine.isSupported) {
      setState(() {
        _isReading = false;
        _message =
            'OCR cannot run inside the web preview. It will run when '
            'Roster Buddy is installed as a native app on your iPhone.';
      });
      return;
    }

    try {
      final SmartScanResult result = await SmartScanEngine.recogniseImage(
        bytes: widget.bytes,
        fileName: widget.fileName,
      );

      if (!mounted) return;

      setState(() {
        _result = result;
        _isReading = false;

        if (!result.hasText) {
          _message = 'No readable text was detected in this image.';
        }
      });
    } on SmartScanException catch (error) {
      if (!mounted) return;

      setState(() {
        _isReading = false;
        _message = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isReading = false;
        _message = 'Roster Buddy could not read this document.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: navy,
        title: const Text(
          'Smart Scan results',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: railwayBlue.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.document_scanner_outlined,
                                  color: railwayBlue,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.documentType,
                                      style: const TextStyle(
                                        color: navy,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      widget.fileName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: textGrey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isReading)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 18),
                                Text(
                                  'Reading document text…',
                                  style: TextStyle(
                                    color: navy,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (_message != null)
                        Card(
                          color: railwayBlue.withValues(alpha: 0.07),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: railwayBlue,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _message!,
                                    style: const TextStyle(
                                      color: navy,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_result != null && _result!.hasText) ...[
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.text_snippet_outlined),
                            ),
                            title: const Text(
                              'Text detected',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${_result!.lines.length} text lines found',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: SelectableText(
                              _result!.fullText,
                              style: const TextStyle(
                                color: navy,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE1E8EF))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isReading
                              ? null
                              : () {
                                  Navigator.of(context).pop(false);
                                },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isReading
                              ? null
                              : () {
                                  Navigator.of(context).pop(true);
                                },
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
