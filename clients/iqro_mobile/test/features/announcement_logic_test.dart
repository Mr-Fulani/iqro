import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/announcements/announcement_logic.dart';

// The same cases as services/web/lib/announcements.test.ts. The desktop card
// and step window are site-only, so their cases check the bubble instead.

const _day = Duration(days: 1);
final _now = DateTime.parse('2026-10-22T10:00:00Z');
const _idA = '01a16092-1950-77f9-9d76-0ea6de5279b8';
const _idB = '01a16092-1950-77f9-9d76-0ea6de5279b9';

Map<String, Object?> _payload([Map<String, Object?> overrides = const {}]) =>
    <String, Object?>{
      'id': _idA,
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
      'title': 'Новый чтец',
      'summary': '114 сур',
      'body': '',
      'image': null,
      'steps': <Object?>[],
      'action': <String, Object?>{
        'type': 'reciter',
        'label': 'Послушать',
        'web_path': '/ru/audio?reciter=x',
        'app_route': '/audio/reciter/x',
        'external_url': null,
      },
      'version': 'v1',
      ...overrides,
    };

Announcement _item([Map<String, Object?> overrides = const {}]) {
  final parsed = parseAnnouncements(<String, Object?>{
    'results': <Object?>[_payload(overrides)],
  });
  expect(parsed, hasLength(1));
  return parsed.single;
}

List<String> _ids(List<Announcement> items) =>
    items.map((item) => item.id).toList();

void main() {
  test(
    'parsing keeps valid announcements and drops broken or unsafe parts',
    () {
      final items = parseAnnouncements(<String, Object?>{
        'results': <Object?>[
          _payload(),
          _payload(<String, Object?>{'id': 'not-a-uuid'}),
          _payload(<String, Object?>{
            'id': _idB,
            'action': <String, Object?>{
              'type': 'external',
              'label': 'x',
              'web_path': '//evil.example',
              'app_route': '//evil.example',
              'external_url': 'https://evil.example',
            },
          }),
        ],
      });
      expect(items, hasLength(2));
      expect(items[1].action.webPath, isNull);
      expect(items[1].action.appRoute, isNull);
      expect(items[1].action.externalUrl, isNull);
      expect(parseAnnouncements(null), isEmpty);
      final feed = parseAnnouncementFeed(<String, Object?>{
        'next_cursor': 'abc',
        'results': <Object?>[],
      });
      expect(feed.nextCursor, 'abc');
      expect(feed.results, isEmpty);
    },
  );

  test('read or closed announcements leave the home screen', () {
    final first = _item();
    final second = _item(<String, Object?>{'id': _idB});
    var state = const AnnouncementLocalState();
    expect(_ids(bubbleAnnouncements([first, second], state, _now, {})), [
      _idA,
      _idB,
    ]);
    state = markDismissed(state, _idA, _now);
    expect(_ids(bubbleAnnouncements([first, second], state, _now, {})), [_idB]);
    state = markRead(state, _idB, _now);
    expect(bubbleAnnouncements([first, second], state, _now, {}), isEmpty);
  });

  test("the bubble follows the admin's frequency and impression limit", () {
    final daily = _item();
    var state = const AnnouncementLocalState();
    const noSession = <String>{};
    expect(_ids(bubbleAnnouncements([daily], state, _now, noSession)), [_idA]);

    state = recordBubbleShown(state, [daily], _now, noSession);
    expect(state.bubble[_idA]!.shown, 1);
    // Shown today: hidden on the next visit, but kept while this session lasts.
    final later = _now.add(const Duration(seconds: 1));
    expect(bubbleAnnouncements([daily], state, later, noSession), isEmpty);
    expect(bubbleAnnouncements([daily], state, later, {_idA}), hasLength(1));
    expect(
      bubbleAnnouncements([daily], state, _now.add(_day), noSession),
      hasLength(1),
    );

    state = recordBubbleShown(state, [daily], _now.add(_day), noSession);
    state = recordBubbleShown(state, [daily], _now.add(_day * 2), noSession);
    expect(state.bubble[_idA]!.shown, 3);
    expect(
      bubbleAnnouncements([daily], state, _now.add(_day * 10), noSession),
      isEmpty,
    );

    final weekly = _item(<String, Object?>{
      'id': _idB,
      'bubble': <String, Object?>{
        'icon': 'sparkle',
        'frequency': 'weekly',
        'max_impressions': 5,
      },
    });
    final seen = recordBubbleShown(
      const AnnouncementLocalState(),
      [weekly],
      _now,
      noSession,
    );
    expect(
      bubbleAnnouncements([weekly], seen, _now.add(_day * 6), noSession),
      isEmpty,
    );
    expect(
      bubbleAnnouncements([weekly], seen, _now.add(_day * 7), noSession),
      hasLength(1),
    );
  });

  test('every visit and every three days are counted from the last show', () {
    final eachVisit = _item(<String, Object?>{
      'bubble': <String, Object?>{
        'icon': 'sparkle',
        'frequency': 'each_visit',
        'max_impressions': 2,
      },
    });
    var state = recordBubbleShown(
      const AnnouncementLocalState(),
      [eachVisit],
      _now,
      {},
    );
    expect(bubbleAnnouncements([eachVisit], state, _now, {}), hasLength(1));
    state = recordBubbleShown(state, [eachVisit], _now, {});
    expect(bubbleAnnouncements([eachVisit], state, _now, {}), isEmpty);

    final everyThree = _item(<String, Object?>{
      'bubble': <String, Object?>{
        'icon': 'sparkle',
        'frequency': 'every_3_days',
        'max_impressions': 5,
      },
    });
    final seen = recordBubbleShown(
      const AnnouncementLocalState(),
      [everyThree],
      _now,
      {},
    );
    expect(
      bubbleAnnouncements([everyThree], seen, _now.add(_day * 2), {}),
      isEmpty,
    );
    expect(
      bubbleAnnouncements([everyThree], seen, _now.add(_day * 3), {}),
      hasLength(1),
    );
  });

  test('fundraising and read announcements never ride the bubble', () {
    final fundraising = _item(<String, Object?>{'kind': 'fundraising'});
    expect(
      bubbleAnnouncements(
        [fundraising],
        const AnnouncementLocalState(),
        _now,
        {},
      ),
      isEmpty,
    );
    final read = markRead(const AnnouncementLocalState(), _idA, _now);
    expect(bubbleAnnouncements([_item()], read, _now, {}), isEmpty);
  });

  test('audience, receipts and impressions', () {
    final guests = _item(<String, Object?>{
      'audience': <String, Object?>{'auth': 'guests'},
    });
    final members = _item(<String, Object?>{
      'id': _idB,
      'audience': <String, Object?>{'auth': 'signed_in'},
    });
    expect(_ids(forAudience([guests, members], false)), [_idA]);
    expect(_ids(forAudience([guests, members], true)), [_idB]);

    final local = markRead(const AnnouncementLocalState(), _idA, _now);
    final merged = mergeReceipts(local, <String, Object?>{
      'results': <Object?>[
        <String, Object?>{
          'announcement_id': _idA,
          'read_at': '2020-01-01T00:00:00Z',
          'dismissed_at': null,
        },
        <String, Object?>{
          'announcement_id': _idB,
          'read_at': null,
          'dismissed_at': '2026-10-20T00:00:00Z',
        },
      ],
    });
    expect(merged.read[_idA], local.read[_idA]);
    expect(merged.dismissed[_idB], '2026-10-20T00:00:00Z');

    final first = takeImpression(
      const AnnouncementLocalState(),
      _idA,
      'bubble',
      _now,
    );
    expect(first.fresh, isTrue);
    expect(
      takeImpression(
        first.state,
        _idA,
        'bubble',
        _now.add(const Duration(seconds: 1)),
      ).fresh,
      isFalse,
    );
    expect(
      takeImpression(first.state, _idA, 'bubble', _now.add(_day)).fresh,
      isTrue,
    );
  });

  test('stored state survives garbage', () {
    expect(parseLocalState('not json').toJson(), {
      'read': <String, String>{},
      'dismissed': <String, String>{},
      'waves': <String, int>{},
      'bubble': <String, Object?>{},
      'impressions': <String, String>{},
    });
    final stored = parseLocalState(
      jsonDecode(
        jsonEncode(<String, Object?>{
          'read': <String, Object?>{_idA: 'x', 'junk': 'y'},
          'bubble': <String, Object?>{
            _idA: <String, Object?>{'shown': 2, 'last': 'z'},
          },
        }),
      ),
    );
    expect(stored.read.keys, [_idA]);
    expect(stored.bubble[_idA]!.shown, 2);

    // A saved state reads back the same.
    final state = recordBubbleShown(
      markRead(const AnnouncementLocalState(), _idA, _now, 2),
      [
        _item(<String, Object?>{'id': _idB}),
      ],
      _now,
      {},
    );
    final restored = parseLocalState(jsonDecode(jsonEncode(state.toJson())));
    expect(restored.toJson(), state.toJson());
  });

  test('the body supports paragraphs, lists and bold only', () {
    expect(bodyBlocks('Первый абзац\nвторая строка\n\n- один\n- два'), [
      const BodyBlock(list: false, lines: ['Первый абзац', 'вторая строка']),
      const BodyBlock(list: true, lines: ['один', 'два']),
    ]);
    expect(boldSegments('Нажмите **Кибла** внизу'), [
      (text: 'Нажмите ', bold: false),
      (text: 'Кибла', bold: true),
      (text: ' внизу', bold: false),
    ]);
  });

  test('a mark hides the announcement only in its own wave', () {
    final first = _item();
    var state = markDismissed(const AnnouncementLocalState(), _idA, _now, 1);
    expect(isFinished(first, state), isTrue);
    expect(bubbleAnnouncements([first], state, _now, {}), isEmpty);

    // «Показать снова»: the same announcement in wave 2 is back on the home
    // screen.
    final again = _item(<String, Object?>{'wave': 2});
    expect(isFinished(again, state), isFalse);
    expect(_ids(bubbleAnnouncements([again], state, _now, {})), [_idA]);
    state = markDismissed(state, _idA, _now.add(_day), 2);
    expect(isFinished(again, state), isTrue);
    expect(state.dismissed[_idA], _now.toIso8601String());

    // Marks saved before waves existed count as wave 1; the feed's "read"
    // stays.
    final legacy = parseLocalState(<String, Object?>{
      'read': <String, Object?>{_idA: '2026-10-21T10:00:00Z'},
    });
    expect(isFinished(first, legacy), isTrue);
    expect(isFinished(again, legacy), isFalse);
    expect(markRead(legacy, _idA, _now, 2).read[_idA], '2026-10-21T10:00:00Z');
  });

  test("the bubble's frequency and limit start over in each wave", () {
    final first = _item();
    const noSession = <String>{};
    var state = const AnnouncementLocalState();
    for (var day = 0; day < 3; day += 1) {
      state = recordBubbleShown(
        state,
        [first],
        _now.add(_day * day),
        noSession,
      );
    }
    expect(
      bubbleAnnouncements([first], state, _now.add(_day * 10), noSession),
      isEmpty,
    );

    final again = _item(<String, Object?>{'wave': 2});
    expect(
      bubbleAnnouncements([again], state, _now.add(_day * 10), noSession),
      hasLength(1),
    );
    state = recordBubbleShown(state, [again], _now.add(_day * 10), noSession);
    expect(
      state.bubble[_idA],
      BubbleSeen(
        shown: 1,
        last: _now.add(_day * 10).toIso8601String(),
        wave: 2,
      ),
    );
  });

  test('receipts and impressions carry the wave', () {
    final merged = mergeReceipts(
      const AnnouncementLocalState(),
      <String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'announcement_id': _idA,
            'read_at': null,
            'dismissed_at': '2026-10-20T00:00:00Z',
            'wave': 3,
          },
        ],
      },
    );
    expect(isFinished(_item(<String, Object?>{'wave': 3}), merged), isTrue);
    expect(isFinished(_item(<String, Object?>{'wave': 4}), merged), isFalse);

    final first = takeImpression(
      const AnnouncementLocalState(),
      _idA,
      'bubble',
      _now,
      1,
    );
    expect(takeImpression(first.state, _idA, 'bubble', _now, 2).fresh, isTrue);
    expect(_item().wave, 1);
  });
}
