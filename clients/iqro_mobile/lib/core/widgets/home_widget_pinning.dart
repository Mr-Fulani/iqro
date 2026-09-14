import 'dart:io';

import 'package:home_widget/home_widget.dart';

enum HomeWidgetPinResult { unsupported, requested, alreadyInstalled }

final homeWidgetPinning = HomeWidgetPinning();

/// Checks the launcher each time so removing a widget allows adding it again.
class HomeWidgetPinning {
  HomeWidgetPinning({
    bool Function()? isAndroid,
    Future<List<HomeWidgetInfo>> Function()? installedWidgets,
    Future<bool?> Function()? supportsPinning,
    Future<void> Function(String)? pin,
  }) : _isAndroid = isAndroid ?? (() => Platform.isAndroid),
       _installedWidgets = installedWidgets ?? HomeWidget.getInstalledWidgets,
       _supportsPinning =
           supportsPinning ?? HomeWidget.isRequestPinWidgetSupported,
       _pin = pin ?? ((name) => HomeWidget.requestPinWidget(androidName: name));

  final bool Function() _isAndroid;
  final Future<List<HomeWidgetInfo>> Function() _installedWidgets;
  final Future<bool?> Function() _supportsPinning;
  final Future<void> Function(String) _pin;
  final _pending = <String, Future<HomeWidgetPinResult>>{};

  Future<HomeWidgetPinResult> request(String receiver) =>
      _pending[receiver] ??= _request(receiver).whenComplete(() {
        _pending.remove(receiver);
      });

  Future<HomeWidgetPinResult> _request(String receiver) async {
    if (!_isAndroid()) return HomeWidgetPinResult.unsupported;
    final installed = await _installedWidgets();
    if (installed.any(
      (widget) => widget.androidClassName?.split('.').last == receiver,
    )) {
      return HomeWidgetPinResult.alreadyInstalled;
    }
    if (await _supportsPinning() != true) {
      return HomeWidgetPinResult.unsupported;
    }
    await _pin(receiver);
    return HomeWidgetPinResult.requested;
  }
}
