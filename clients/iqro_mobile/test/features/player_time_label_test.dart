import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/player_screen.dart';

void main() {
  test('a timeline under an hour reads minutes and seconds', () {
    const total = Duration(minutes: 25, seconds: 2);
    expect(
      playerTimeLabel(const Duration(minutes: 4, seconds: 54), total: total),
      '04:54',
    );
    expect(playerTimeLabel(total, total: total), '25:02');
  });

  test('a timeline of an hour or more keeps the hours on both ends', () {
    const total = Duration(hours: 1, minutes: 9, seconds: 32);
    expect(playerTimeLabel(total, total: total), '1:09:32');
    expect(
      playerTimeLabel(const Duration(minutes: 50, seconds: 59), total: total),
      '0:50:59',
    );
  });
}
