import 'package:flutter/material.dart';

class ZamLogo extends StatelessWidget {
  const ZamLogo({
    super.key,
    required this.size,
    this.fontSize,
  });

  final double size;
  final double? fontSize;

  static const String assetPath = 'assets/images/zam-logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(
        child: Text(
          'Z',
          style: TextStyle(
            color: Colors.transparent,
            fontWeight: FontWeight.bold,
            fontSize: fontSize ?? size * 0.45,
          ),
        ),
      ),
    );
  }
}
