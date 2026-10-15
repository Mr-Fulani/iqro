import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';

void main() {
  test('equal brand colors compare equal so themes do not churn', () {
    const colors = IqroColors(
      ink: Color(0xFF111111),
      inkSoft: Color(0xFF222222),
      sand: Color(0xFF333333),
      lavender: Color(0xFF444444),
      gold: Color(0xFF555555),
      panelSoft: Color(0xFF666666),
      line: Color(0xFF777777),
    );

    expect(colors.copyWith(), colors);
    expect(colors.copyWith().hashCode, colors.hashCode);
    expect(colors.copyWith(gold: const Color(0xFF000000)), isNot(colors));
    expect(
      IqroTheme.light().extension<IqroColors>(),
      IqroTheme.light().extension<IqroColors>(),
    );
  });
}
