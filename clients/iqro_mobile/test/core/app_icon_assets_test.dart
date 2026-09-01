import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple app icons cover every declared size without transparency', () {
    const expected = <String, int>{
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    const directory = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

    for (final entry in expected.entries) {
      final header = _pngHeader('$directory/${entry.key}');
      expect(header.width, entry.value, reason: entry.key);
      expect(header.height, entry.value, reason: entry.key);
      expect(header.bitDepth, 8, reason: entry.key);
      expect(header.colorType, 2, reason: '${entry.key} must be RGB');
    }
  });

  test('launch images are transparent square IQRO marks', () {
    const expected = <String, int>{
      'LaunchImage.png': 108,
      'LaunchImage@2x.png': 216,
      'LaunchImage@3x.png': 324,
    };
    const directory = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

    for (final entry in expected.entries) {
      final header = _pngHeader('$directory/${entry.key}');
      expect(header.width, entry.value, reason: entry.key);
      expect(header.height, entry.value, reason: entry.key);
      expect(header.bitDepth, 8, reason: entry.key);
      expect(header.colorType, 6, reason: '${entry.key} must preserve alpha');
    }
  });

  test('legacy Android icons use the same opaque IQRO artwork', () {
    const expected = <String, int>{
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };

    for (final entry in expected.entries) {
      final header = _pngHeader(
        'android/app/src/main/res/${entry.key}/ic_launcher.png',
      );
      expect(header.width, entry.value, reason: entry.key);
      expect(header.height, entry.value, reason: entry.key);
      expect(header.colorType, 2, reason: '${entry.key} must be RGB');
    }
  });
}

({int width, int height, int bitDepth, int colorType}) _pngHeader(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(
    bytes.take(8),
    orderedEquals(const <int>[137, 80, 78, 71, 13, 10, 26, 10]),
    reason: path,
  );
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    bitDepth: data.getUint8(24),
    colorType: data.getUint8(25),
  );
}
