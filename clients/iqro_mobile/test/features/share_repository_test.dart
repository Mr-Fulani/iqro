import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/share/share_repository.dart';

void main() {
  test('share analytics keeps only a coarse OS major version', () {
    expect(shareOsMajor('17.6.1'), '17');
    expect(shareOsMajor('Android 14'), '14');
    expect(shareOsMajor('unknown'), 'unknown');
  });
}
