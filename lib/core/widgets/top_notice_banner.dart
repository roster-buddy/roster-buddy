import 'dart:async';
import 'package:flutter/material.dart';

class TopNoticeBanner {
  OverlayEntry? _entry;
  Timer? _timer;

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  void show(BuildContext context, {required String message, required VoidCallback onView}) {
    dismiss();
    _entry = OverlayEntry(builder: (context) => Positioned(
      top: MediaQuery.paddingOf(context).top + 8, left: 12, right: 12,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Semantics(liveRegion: true, child: Material(
          color: const Color(0xFF102A43), elevation: 6,
          borderRadius: BorderRadius.circular(14),
          child: Padding(padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(children: [
              const Icon(Icons.notifications_outlined, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () { dismiss(); onView(); },
                child: const Text('View'),
              ),
            ]),
          ),
        )),
      )),
    ));
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _timer = Timer(const Duration(seconds: 4), dismiss);
  }
}
