import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/platform/reader_haptics.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final native = <MethodCall>[];
  final standard = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native.clear();
    standard.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ReaderHaptics.channel,
      (call) async {
        native.add(call);
        return 'played';
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        standard.add(call);
        return null;
      },
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ReaderHaptics.channel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  test('Android uses one native pulse, not two feedback mechanisms', () async {
    await ReaderHaptics.pageChanged(enabled: true);
    expect(native.single.method, 'pageTick');
    expect(standard, isEmpty);
  });
  test('app preference disables all feedback', () async {
    await ReaderHaptics.pageChanged(enabled: false);
    expect(native, isEmpty);
    expect(standard, isEmpty);
  });
  test('system-disabled response must not trigger a fallback pulse', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ReaderHaptics.channel,
      (_) async => 'disabled',
    );
    await ReaderHaptics.pageChanged(enabled: true);
    expect(standard, isEmpty);
  });
  test('older Android shell has a safe standard fallback', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ReaderHaptics.channel,
      null,
    );
    await ReaderHaptics.pageChanged(enabled: true);
    expect(standard.single.arguments, 'HapticFeedbackType.lightImpact');
  });
  test('iOS uses native Flutter impact without Android channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await ReaderHaptics.pageChanged(enabled: true);
    expect(native, isEmpty);
    expect(standard.single.arguments, 'HapticFeedbackType.lightImpact');
  });
}
