import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/features/announcements/announcement_logic.dart';
import 'package:iqro_mobile/features/announcements/announcement_repository.dart';

const announcementIdA = '01a16092-1950-77f9-9d76-0ea6de5279b8';
const announcementIdB = '01a16092-1950-77f9-9d76-0ea6de5279b9';
const announcementIdC = '01a16092-1950-77f9-9d76-0ea6de5279ba';

/// The server's announcement in one language, as the site's tests build it.
Map<String, Object?> announcementPayload([
  Map<String, Object?> overrides = const {},
]) => <String, Object?>{
  'id': announcementIdA,
  'kind': 'reciter',
  'priority': 'normal',
  'pinned': false,
  'starts_at': '2026-10-21T00:00:00Z',
  'ends_at': '2026-11-04T00:00:00Z',
  'surfaces': <String, Object?>{
    'bubble': true,
    'home_card': true,
    'modal': false,
  },
  'bubble': <String, Object?>{
    'icon': 'portrait',
    'frequency': 'daily',
    'max_impressions': 3,
  },
  'audience': <String, Object?>{'auth': 'all'},
  'title': 'Новый чтец: Ясир ад-Даусари',
  'summary': 'Все 114 сур в спокойном мураттале.',
  'body': '',
  'image': null,
  'steps': <Object?>[],
  'action': <String, Object?>{
    'type': 'reciter',
    'label': 'Послушать',
    'web_path': '/ru/audio?reciter=r1&play=1',
    'app_route': '/audio/reciter/r1?play=1',
    'external_url': null,
  },
  'version': 'v1',
  'wave': 1,
  ...overrides,
};

Announcement testAnnouncement([Map<String, Object?> overrides = const {}]) =>
    parseAnnouncements(<String, Object?>{
      'results': <Object?>[announcementPayload(overrides)],
    }).single;

/// An announcement of a new feature with steps, as the step window shows it.
Announcement featureAnnouncement({String id = announcementIdB}) =>
    testAnnouncement(<String, Object?>{
      'id': id,
      'kind': 'feature',
      'title': 'Компас Киблы',
      'summary': 'Стрелка показывает на Каабу.',
      'body':
          'Откройте **Время намаза** и нажмите на компас.\n\n- Держите '
          'телефон ровно\n- Уберите магниты',
      'bubble': <String, Object?>{
        'icon': 'compass',
        'frequency': 'daily',
        'max_impressions': 5,
      },
      'steps': <Object?>[
        <String, Object?>{'title': 'Откройте раздел', 'text': 'Время намаза'},
        <String, Object?>{'title': 'Нажмите на компас', 'text': ''},
      ],
      'action': <String, Object?>{
        'type': 'screen',
        'label': 'Открыть',
        'web_path': '/ru/prayer?qibla=1',
        'app_route': '/prayer?qibla=1',
        'external_url': null,
      },
    });

AuthSession testSession({String userId = 'user-1', String status = 'active'}) =>
    AuthSession(
      accessToken: 'access-$userId',
      refreshToken: 'refresh-$userId',
      accessExpiresAt: DateTime.utc(2035),
      refreshExpiresAt: DateTime.utc(2036),
      bootstrapGeneration: 1,
      userId: userId,
      userStatus: status,
      deviceId: 'device-$userId',
    );

class FakeSessionController extends StateNotifier<AsyncValue<AuthSession?>>
    implements SessionController {
  FakeSessionController([AuthSession? session]) : super(AsyncData(session));

  set session(AuthSession? value) => state = AsyncData(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The repository without network or database: what the screens asked for
/// and what they sent.
class FakeAnnouncementRepository implements AnnouncementRepository {
  FakeAnnouncementRepository({
    List<Announcement>? active,
    Map<String?, AnnouncementFeedPage>? pages,
    this.receiptsPayload,
  }) : activeItems = active ?? <Announcement>[],
       pages = pages ?? <String?, AnnouncementFeedPage>{};

  List<Announcement> activeItems;
  bool fromCache = false;
  bool offline = false;
  Map<String?, AnnouncementFeedPage> pages;

  /// The second page, served for the cursor `next`.
  AnnouncementFeedPage? nextPage;
  Object? receiptsPayload;
  AnnouncementLocalState stored = const AnnouncementLocalState();
  final sentReceipts = <Map<String, Object?>>[];
  final events = <String>[];
  final feedRequests = <String>[];
  var activeRequests = 0;
  var receiptRequests = 0;
  var flushes = 0;

  @override
  String get platform => 'android';

  @override
  Future<AnnouncementLocalState> loadState() async => stored;

  @override
  Future<void> saveState(AnnouncementLocalState state) async => stored = state;

  @override
  Future<AnnouncementList> active({
    required String locale,
    bool refresh = false,
    DateTime? now,
  }) async {
    activeRequests++;
    if (offline) throw StateError('offline');
    return (items: activeItems, fromCache: fromCache);
  }

  @override
  Future<AnnouncementFeed> feed({
    required String locale,
    String? kind,
    String? cursor,
  }) async {
    feedRequests.add('${kind ?? 'all'}:${cursor ?? ''}');
    if (offline) throw StateError('offline');
    final page = cursor == 'next' ? nextPage : pages[kind];
    return (
      page:
          page ??
          const AnnouncementFeedPage(
            nextCursor: null,
            results: <Announcement>[],
          ),
      fromCache: fromCache,
    );
  }

  @override
  Future<Object?> receipts() async {
    receiptRequests++;
    return receiptsPayload;
  }

  @override
  Future<void> sendReceipt(
    String id, {
    bool read = false,
    bool dismissed = false,
    required int wave,
  }) async {
    sentReceipts.add(<String, Object?>{
      'id': id,
      if (read) 'read': true,
      if (dismissed) 'dismissed': true,
      'wave': wave,
    });
  }

  @override
  void track(String id, String surface, String event, int wave) =>
      events.add('$id:$surface:$event:$wave');

  @override
  Future<void> flushEvents() async => flushes++;

  @override
  int get pendingEvents => events.length;
}

/// A one-pixel image for portraits in widget tests.
final testImageProvider = MemoryImage(
  Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xE0, 0x8E, 0xF5, 0xFA,
    0x0F, 0x00, 0x02, 0xDB, 0x01, 0xB2, 0x0A, 0xE4, 0x34, 0xCC, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]),
);
