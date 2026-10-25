import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/listening_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final logo = Uri.file('/app/iqro-reciter-default-v1.webp');

  test(
    'background player uses the local default figure when no portrait exists',
    () {
      final handler = ListeningMediaService(defaultArtwork: logo);
      handler.publish(
        item: const MediaItem(id: 'track', title: 'Al-Fatiha'),
      );
      expect(handler.mediaItem.value?.artUri, logo);
      handler.publish(item: null);
      expect(handler.mediaItem.value, isNull);
    },
  );

  test('background player preserves explicit reciter artwork', () {
    final handler = ListeningMediaService(defaultArtwork: logo);
    final portrait = Uri.https('iqro.forum', '/reciter.png');
    handler.publish(
      item: MediaItem(id: 'track', title: 'Al-Fatiha', artUri: portrait),
    );
    expect(handler.mediaItem.value?.artUri, portrait);
  });
}
