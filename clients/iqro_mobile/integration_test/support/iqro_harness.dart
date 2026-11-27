import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iqro_mobile/app/app.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real app on a simulator: preferences before launch, waiting for
/// screens, screenshots, and a list of every Dart error the app reported.
class IqroHarness {
  IqroHarness._(this.binding);

  factory IqroHarness.initialize() {
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    // Frames as on a phone, so the recording shows the app's own motion.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    return IqroHarness._(binding).._registerExtensions();
  }

  final IntegrationTestWidgetsFlutterBinding binding;
  late WidgetTester tester;
  late AppLocalizations l10n;

  /// The interface language: the driver's IQRO_LOCALE, else the default.
  late String locale;

  /// The driver's IQRO_MODE: `setup` for a run that only prepares the
  /// install (store_screenshots_test.dart); empty otherwise.
  var mode = '';

  /// In CI the driver on the Mac (driver/iqro_driver.dart) saves the
  /// simulator's screen, with its status bar, whenever the test asks.
  var _host = false;
  final errors = <String>[];
  final _steps = <String>[];
  var _shots = 0;
  Completer<void>? _hostShot;
  String? _hostShotName;
  // The driver connects a little after the app starts; a request posted
  // before it listens would be lost. It brings the run's settings.
  final _driverReady = Completer<Map<String, String>>();

  /// Runs [body] with every reported error recorded, then prints a summary.
  ///
  /// flutter_test still fails the test on the first reported error; the list
  /// makes the log say every one of them, not only the first.
  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    this.tester = tester;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final source = details.library ?? 'unknown';
      errors.add('$source: ${details.exceptionAsString()}');
      debugPrint('IQRO ERROR [$source] ${details.exceptionAsString()}');
      previous?.call(details);
    };
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
      debugPrint(
        'IQRO SUMMARY ${_steps.length} steps, ${errors.length} errors',
      );
      for (final step in _steps) {
        debugPrint('IQRO SUMMARY step $step');
      }
      for (final error in errors) {
        debugPrint('IQRO SUMMARY error $error');
      }
    }
  }

  /// Waits for the driver (none when run with `flutter test`), then sets the
  /// preferences the app reads at launch (lib/core/storage/preferences_store.dart).
  Future<void> prepare({
    String locale = 'ru',
    bool onboardingComplete = true,
    bool playIntro = false,
    bool quiet = false,
  }) async {
    try {
      final settings = await _driverReady.future.timeout(
        const Duration(seconds: 30),
      );
      _host = true;
      final asked = settings['locale'] ?? '';
      if (asked.isNotEmpty) locale = asked;
      mode = settings['mode'] ?? '';
    } on TimeoutException {
      debugPrint('IQRO NOTE no driver: screenshots are not saved');
    }
    this.locale = locale;
    l10n = lookupAppLocalizations(Locale(locale));
    debugPrint('IQRO LOCALE $locale');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('locale', locale);
    await preferences.setBool('onboarding_complete', onboardingComplete);
    await preferences.setBool('startup_intro_seen_v1', !playIntro);
    await preferences.setString('theme_mode', 'light');
    await preferences.setBool('mushaf_night', false);
    // Never asks the store-run apps to send analytics (no consent card).
    await preferences.setString('iqro_analytics_consent_v1', 'denied');
    if (quiet) {
      // Store screenshots: no first-use hints over the screens.
      await preferences.setInt('player_hint_count', 5);
      await preferences.setInt('reader_swipe_hint_count', 3);
      await preferences.setBool('reminder_sound_checked', true);
      await preferences.setBool('recitation_notice_seen', true);
    }
  }

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(IqroApp)));

  GoRouter get router =>
      GoRouter.of(tester.element(find.byType(Navigator).first));

  /// Pumps frames for [duration] of real time.
  Future<void> settle([Duration duration = const Duration(seconds: 1)]) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Waits until [finder] finds something. Does not need the app to be idle:
  /// several screens animate for ever (`pumpAndSettle` would never return).
  Future<void> waitFor(
    Finder finder, {
    required String what,
    Duration timeout = const Duration(seconds: 60),
  }) => _waitUntil(() => finder.evaluate().isNotEmpty, what, timeout);

  Future<void> waitForNone(
    Finder finder, {
    required String what,
    Duration timeout = const Duration(seconds: 60),
  }) => _waitUntil(() => finder.evaluate().isEmpty, what, timeout);

  Future<void> waitUntil(
    bool Function() done, {
    required String what,
    Duration timeout = const Duration(seconds: 60),
  }) => _waitUntil(done, what, timeout);

  /// Leaves the screen opened with `router.push`.
  void back() {
    if (router.canPop()) router.pop();
  }

  Future<void> _waitUntil(
    bool Function() done,
    String what,
    Duration timeout,
  ) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) {
        await screenshot(
          'timeout-${what.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
        );
        throw TestFailure('Did not see $what within ${timeout.inSeconds} s');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Waits for the loading spinners inside [scope] to go (IqroLoading is
  /// Cupertino's activity indicator on iOS).
  Future<void> waitForLoaded({
    required Finder scope,
    required String what,
    Duration timeout = const Duration(seconds: 60),
  }) => waitForNone(
    find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IqroLoading ||
            widget is ProgressIndicator ||
            widget is CupertinoActivityIndicator,
      ),
    ),
    what: '$what loaded',
    timeout: timeout,
  );

  Future<void> tap(Finder finder, {required String what}) async {
    await waitFor(finder, what: what);
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(finder.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// A tab of the bottom bar, by its label.
  Future<void> openTab(String label) => tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
    what: 'the "$label" tab',
  );

  /// Records a passed step and saves the screen as `NN-name.png`.
  Future<void> step(String name, {String note = ''}) async {
    // Long enough for the pointer marks of the last tap to fade out.
    await settle(const Duration(milliseconds: 1500));
    _steps.add(note.isEmpty ? name : '$name: $note');
    debugPrint('IQRO STEP $name ${note.isEmpty ? 'ok' : note}');
    await screenshot(name);
  }

  /// Saves the simulator screen through the driver on the Mac.
  Future<void> screenshot(String name) async {
    _shots += 1;
    final file = '${_shots.toString().padLeft(2, '0')}-$name';
    if (!_host) {
      debugPrint('IQRO SHOT $file (not saved: no driver)');
      return;
    }
    final done = Completer<void>();
    _hostShot = done;
    _hostShotName = file;
    developer.postEvent('iqro.screenshot', <String, Object?>{'name': file});
    try {
      await done.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      debugPrint('IQRO SHOT $file: the host did not answer');
    } finally {
      _hostShot = null;
    }
  }

  /// The driver (driver/iqro_driver.dart) calls these.
  void _registerExtensions() {
    developer.registerExtension('ext.iqro.driverReady', (method, params) async {
      if (!_driverReady.isCompleted) _driverReady.complete(params);
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': true}),
      );
    });
    developer.registerExtension('ext.iqro.screenshotSaved', (
      method,
      params,
    ) async {
      // Only the answer for the screenshot asked last: a late answer for one
      // that timed out must not move the test on early.
      final shot = _hostShot;
      if (shot != null &&
          !shot.isCompleted &&
          params['name'] == _hostShotName) {
        shot.complete();
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': true}),
      );
    });
  }

  /// How many pixels of each strong colour [finder]'s page shows: the tajweed
  /// colours come from the QCF V4 font's own colour layers, so a page drawn
  /// without them is black text only.
  Future<Map<String, int>> colours(Finder finder) async {
    final page = finder.evaluate().first.renderObject! as RenderBox;
    RenderObject? render = page;
    while (render != null && render is! RenderRepaintBoundary) {
      render = render.parent;
    }
    if (render is! RenderRepaintBoundary) {
      throw TestFailure('No repaint boundary above the Mushaf page');
    }
    // At the screen's own resolution: at 1x the coloured glyph strokes are
    // too few pixels for a steady count.
    final ratio = tester.view.devicePixelRatio;
    final image = await render.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (bytes == null) throw TestFailure('The Mushaf page could not be read');
    // Only the page itself: the legend's coloured chips below it must not
    // pass for tajweed drawn by the font.
    final area = (page.localToGlobal(Offset.zero, ancestor: render) & page.size)
        .shift(Offset.zero);
    final scaled = Rect.fromLTRB(
      area.left * ratio,
      area.top * ratio,
      area.right * ratio,
      area.bottom * ratio,
    );
    final left = scaled.left.floor().clamp(0, width);
    final right = scaled.right.ceil().clamp(0, width);
    final top = scaled.top.floor().clamp(0, height);
    final bottom = scaled.bottom.ceil().clamp(0, height);
    const names = <String>[
      'red',
      'orange',
      'yellow',
      'green',
      'cyan',
      'blue',
      'purple',
      'pink',
    ];
    final counts = <String, int>{for (final name in names) name: 0};
    for (var y = top; y < bottom; y += 2) {
      for (var x = left; x < right; x += 2) {
        final i = (y * width + x) * 4;
        final r = bytes.getUint8(i) / 255;
        final g = bytes.getUint8(i + 1) / 255;
        final b = bytes.getUint8(i + 2) / 255;
        final high = math.max(r, math.max(g, b));
        final low = math.min(r, math.min(g, b));
        // Strong colours only: black text, cream paper and grey lines are out.
        if (high < 0.35 || high - low < 0.35) continue;
        var hue = 0.0;
        final span = high - low;
        if (high == r) {
          hue = 60 * (((g - b) / span) % 6);
        } else if (high == g) {
          hue = 60 * ((b - r) / span + 2);
        } else {
          hue = 60 * ((r - g) / span + 4);
        }
        if (hue < 0) hue += 360;
        final name = switch (hue) {
          < 15 || >= 345 => 'red',
          < 45 => 'orange',
          < 70 => 'yellow',
          < 165 => 'green',
          < 200 => 'cyan',
          < 255 => 'blue',
          < 300 => 'purple',
          _ => 'pink',
        };
        counts[name] = counts[name]! + 1;
      }
    }
    return counts;
  }
}

/// The platform the test runs on, for the log.
String get platformName =>
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
