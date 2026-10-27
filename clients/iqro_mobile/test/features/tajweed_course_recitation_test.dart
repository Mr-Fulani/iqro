import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';

void main() {
  final murattal = _recitation('qf-6-murattal', 'murattal');
  final afasy = _recitation('qf-7-murattal', 'murattal');
  final teaching = _recitation(
    'qf-6-murattal-teaching',
    'murattal',
    teaching: true,
  );
  final muallim = _recitation('qf-12-muallim', 'muallim');
  final listeningOnly = _recitation('qf-12-listen', 'muallim', timed: false);

  Future<String?> courseRecitation(
    List<Recitation> catalog, {
    String? mushafRecitationId,
  }) async {
    final container = ProviderContainer(
      overrides: <Override>[
        audioRepositoryProvider.overrideWithValue(_AudioRepository(catalog)),
        appPreferencesProvider.overrideWith(
          (ref) => _Preferences(
            const AppPreferences.defaults().copyWith(
              mushafRecitationId: mushafRecitationId,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(tajweedCourseRecitationProvider)();
  }

  test('the tajweed course always plays al-Husary\'s Muallim', () async {
    final catalog = <Recitation>[listeningOnly, murattal, teaching, muallim];
    expect(await courseRecitation(catalog), muallim.id);
    // The Mushaf choice does not change the course voice.
    expect(
      await courseRecitation(catalog, mushafRecitationId: murattal.id),
      muallim.id,
    );
  });

  test('without the Muallim the course falls back to the teaching reciter, '
      'then al-Afasy, then the first one', () async {
    expect(
      await courseRecitation(<Recitation>[murattal, afasy, teaching]),
      teaching.id,
    );
    expect(await courseRecitation(<Recitation>[murattal, afasy]), afasy.id);
    expect(await courseRecitation(<Recitation>[murattal]), murattal.id);
    // A recording that is not timed ayah by ayah cannot play the examples.
    expect(await courseRecitation(<Recitation>[listeningOnly]), isNull);
  });
}

Recitation _recitation(
  String code,
  String style, {
  bool teaching = false,
  bool timed = true,
}) => Recitation(
  id: '$code-id',
  code: code,
  reciter: Reciter(
    id: '$code-reciter',
    slug: code,
    nameAr: 'قارئ',
    nameEn: 'Reciter',
    nameRu: 'Чтец',
    nameTr: 'Kâri',
    biographyAr: '',
    biographyEn: '',
    biographyRu: '',
    biographyTr: '',
  ),
  style: style,
  timingsAvailable: timed,
  timingsComplete: timed,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
  teachingDefault: teaching,
);

class _AudioRepository implements AudioRepository {
  _AudioRepository(this.items);

  final List<Recitation> items;

  @override
  Future<List<Recitation>> recitationsForRole(
    AudioRecitationRole role, {
    bool forceRefresh = false,
  }) async => items.where((item) => item.supports(role)).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences extends StateNotifier<AppPreferences>
    implements AppPreferencesController {
  _Preferences(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
