import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/features/prayer/prayer_location_gateway.dart';

void main() {
  test(
    'reports disabled device location before requesting permission',
    () async {
      final gateway = _FakePrayerLocationGateway(serviceEnabled: false);

      await expectLater(
        acquirePrayerDeviceLocation(gateway),
        throwsA(_apiError('location_disabled')),
      );
      expect(gateway.permissionRequests, 0);
    },
  );

  test('requests permission once and reports a recoverable denial', () async {
    final gateway = _FakePrayerLocationGateway(
      checkedPermission: PrayerLocationPermission.denied,
      requestedPermission: PrayerLocationPermission.denied,
    );

    await expectLater(
      acquirePrayerDeviceLocation(gateway),
      throwsA(_apiError('location_denied')),
    );
    expect(gateway.permissionRequests, 1);
  });

  test('distinguishes a permanent permission denial', () async {
    final gateway = _FakePrayerLocationGateway(
      checkedPermission: PrayerLocationPermission.deniedForever,
    );

    await expectLater(
      acquirePrayerDeviceLocation(gateway),
      throwsA(_apiError('location_denied_forever')),
    );
    expect(gateway.permissionRequests, 0);
  });

  test('returns a validated location and device timezone', () async {
    final gateway = _FakePrayerLocationGateway(
      checkedPermission: PrayerLocationPermission.granted,
      position: const PrayerDevicePosition(
        latitude: 41.0082,
        longitude: 28.9784,
      ),
      timezone: 'Europe/Istanbul',
    );

    final location = await acquirePrayerDeviceLocation(gateway);

    expect(location.latitude, 41.0082);
    expect(location.longitude, 28.9784);
    expect(location.timezone, 'Europe/Istanbul');
    expect(gateway.permissionRequests, 0);
  });

  test('rejects malformed device coordinates without exposing them', () async {
    final gateway = _FakePrayerLocationGateway(
      checkedPermission: PrayerLocationPermission.granted,
      position: const PrayerDevicePosition(latitude: 120, longitude: 28),
    );

    await expectLater(
      acquirePrayerDeviceLocation(gateway),
      throwsA(_apiError('location_unavailable')),
    );
  });
}

Matcher _apiError(String code) =>
    isA<ApiException>().having((error) => error.code, 'code', code);

class _FakePrayerLocationGateway implements PrayerLocationGateway {
  _FakePrayerLocationGateway({
    this.serviceEnabled = true,
    this.checkedPermission = PrayerLocationPermission.granted,
    this.requestedPermission = PrayerLocationPermission.granted,
    this.position = const PrayerDevicePosition(latitude: 41, longitude: 29),
    this.timezone = 'Europe/Istanbul',
  });

  final bool serviceEnabled;
  final PrayerLocationPermission checkedPermission;
  final PrayerLocationPermission requestedPermission;
  final PrayerDevicePosition position;
  final String timezone;
  var permissionRequests = 0;

  @override
  Future<PrayerLocationPermission> checkPermission() async => checkedPermission;

  @override
  Future<PrayerDevicePosition> currentPosition() async => position;

  @override
  Future<String> currentTimezone() async => timezone;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<PrayerLocationPermission> requestPermission() async {
    permissionRequests += 1;
    return requestedPermission;
  }
}
