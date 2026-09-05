import 'package:flutter/material.dart';

const mushafPaperColor = Color(0xFFEDE6D3);
const mushafInkColor = Color(0xFF26261F);

/// Reflowable Quran text on the same paper as the scanned reader. Explicit ink
/// and paper colors keep the Arabic readable in both light and dark app themes.
class MushafAyahText extends StatelessWidget {
  const MushafAyahText({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: mushafPaperColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB7A77F)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFD1C4A4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Text(
            text,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: mushafInkColor,
              fontFamily: 'serif',
              fontSize: 30,
              fontWeight: FontWeight.normal,
              height: 1.85,
            ),
          ),
        ),
      ),
    );
  }
}
