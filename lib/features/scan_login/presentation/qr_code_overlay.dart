import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeOverlay extends StatelessWidget {
  const QrCodeOverlay({
    super.key,
    required this.data,
    required this.statusText,
  });

  final String data;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    if (statusText == null) return QrImage(data: data, size: 220);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter:
              const ColorFilter.mode(Colors.grey, BlendMode.saturation),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child:
                Opacity(opacity: 0.55, child: QrImage(data: data, size: 220)),
          ),
        ),
        Container(
          color: Colors.black45,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(
            statusText!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, height: 1.5),
          ),
        ),
      ],
    );
  }
}
