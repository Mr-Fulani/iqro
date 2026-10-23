// Announcements from /api/v1/announcements: parsing, the marks this device
// keeps (read, dismissed, bubble impressions) and the bubble frequency rules.
// A port of services/web/lib/announcements.ts: the site and the app decide
// alike, and the tests repeat the site's cases.
//
// Waves: «Показать снова» in the admin raises an announcement's `wave`. A read
// or closed mark hides it from the home screen only in the wave it was made in;
// the bubble's frequency and impression limit start over in each wave.

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

const announcementKinds = <String>[
  'reciter',
  'feature',
  'app_release',
  'content',
  'fundraising',
  'general',
];

const _bubbleIntervals = <String, Duration>{
  'each_visit': Duration.zero,
  'daily': Duration(days: 1),
  'every_3_days': Duration(days: 3),
  'weekly': Duration(days: 7),
};

class AnnouncementImage {
  const AnnouncementImage({
    required this.url,
    this.thumbUrl,
    this.width,
    this.height,
    this.alt = '',
  });

  final String url;
  final String? thumbUrl;
  final int? width;
  final int? height;
  final String alt;
}

class AnnouncementStep {
  const AnnouncementStep({
    required this.title,
    this.text = '',
    this.imageUrl,
    this.width,
    this.height,
  });

  final String title;
  final String text;
  final String? imageUrl;
  final int? width;
  final int? height;
}

class AnnouncementAction {
  const AnnouncementAction({
    this.type = 'none',
    this.label = '',
    this.webPath,
    this.appRoute,
    this.externalUrl,
  });

  final String type;
  final String label;
  final String? webPath;
  final String? appRoute;
  final String? externalUrl;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.kind,
    required this.startsAt,
    required this.endsAt,
    required this.title,
    required this.summary,
    this.priority = 'normal',
    this.pinned = false,
    this.bubbleSurface = false,
    this.homeCardSurface = false,
    this.modalSurface = false,
    this.bubbleIcon = 'megaphone',
    this.bubbleFrequency = 'daily',
    this.bubbleMaxImpressions = 5,
    this.audienceAuth = 'all',
    this.body = '',
    this.image,
    this.steps = const <AnnouncementStep>[],
    this.action = const AnnouncementAction(),
    this.version = '',
    this.wave = 1,
  });

  final String id;
  final String kind;
  final String priority;
  final bool pinned;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool bubbleSurface;
  final bool homeCardSurface;
  final bool modalSurface;
  final String bubbleIcon;
  final String bubbleFrequency;
  final int bubbleMaxImpressions;
  final String audienceAuth;
  final String title;
  final String summary;
  final String body;
  final AnnouncementImage? image;
  final List<AnnouncementStep> steps;
  final AnnouncementAction action;
  final String version;
  final int wave;
}

class AnnouncementFeedPage {
  const AnnouncementFeedPage({required this.nextCursor, required this.results});

  final String? nextCursor;
  final List<Announcement> results;
}

class BubbleSeen {
  const BubbleSeen({required this.shown, required this.last, this.wave = 1});

  final int shown;
  final String last;
  final int wave;

  Map<String, Object?> toJson() => <String, Object?>{
    'shown': shown,
    'last': last,
    'wave': wave,
  };

  @override
  bool operator ==(Object other) =>
      other is BubbleSeen &&
      other.shown == shown &&
      other.last == last &&
      other.wave == wave;

  @override
  int get hashCode => Object.hash(shown, last, wave);
}

class AnnouncementLocalState {
  const AnnouncementLocalState({
    this.read = const <String, String>{},
    this.dismissed = const <String, String>{},
    this.waves = const <String, int>{},
    this.bubble = const <String, BubbleSeen>{},
    this.impressions = const <String, String>{},
  });

  final Map<String, String> read;
  final Map<String, String> dismissed;

  /// The latest wave in which each announcement was read or closed.
  final Map<String, int> waves;
  final Map<String, BubbleSeen> bubble;
  final Map<String, String> impressions;

  AnnouncementLocalState copyWith({
    Map<String, String>? read,
    Map<String, String>? dismissed,
    Map<String, int>? waves,
    Map<String, BubbleSeen>? bubble,
    Map<String, String>? impressions,
  }) => AnnouncementLocalState(
    read: read ?? this.read,
    dismissed: dismissed ?? this.dismissed,
    waves: waves ?? this.waves,
    bubble: bubble ?? this.bubble,
    impressions: impressions ?? this.impressions,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'read': read,
    'dismissed': dismissed,
    'waves': waves,
    'bubble': <String, Object?>{
      for (final entry in bubble.entries) entry.key: entry.value.toJson(),
    },
    'impressions': impressions,
  };
}

/// Paths come from the server; only same-site paths are followed in place.
String? safeSitePath(Object? value) {
  if (value is! String || !value.startsWith('/') || value.startsWith('//')) {
    return null;
  }
  return value;
}

int _wave(Object? value) =>
    value is num && value == value.roundToDouble() && value > 0
    ? value.toInt()
    : 1;

int? _int(Object? value) => value is num ? value.toInt() : null;

String? _string(Object? value) => value is String ? value : null;

Announcement? _parseAnnouncement(Object? value) {
  if (value is! Map) return null;
  final id = value['id'];
  final surfaces = value['surfaces'];
  final bubble = value['bubble'];
  final audience = value['audience'];
  final action = value['action'];
  final image = value['image'];
  final steps = value['steps'];
  if (id is! String ||
      !_uuidPattern.hasMatch(id) ||
      !announcementKinds.contains(value['kind']) ||
      value['title'] is! String ||
      value['summary'] is! String ||
      value['starts_at'] is! String ||
      value['ends_at'] is! String ||
      surfaces is! Map ||
      bubble is! Map ||
      audience is! Map ||
      action is! Map ||
      steps is! List) {
    return null;
  }
  final startsAt = DateTime.tryParse(value['starts_at'] as String);
  final endsAt = DateTime.tryParse(value['ends_at'] as String);
  if (startsAt == null || endsAt == null) return null;
  final frequency = bubble['frequency'];
  final maxImpressions = bubble['max_impressions'];
  final priority = value['priority'];
  final auth = audience['auth'];
  final imageUrl = image is Map ? image['url'] : null;
  return Announcement(
    id: id,
    kind: value['kind'] as String,
    priority:
        const <String>['low', 'normal', 'high', 'critical'].contains(priority)
        ? priority as String
        : 'normal',
    pinned: value['pinned'] == true,
    startsAt: startsAt,
    endsAt: endsAt,
    bubbleSurface: surfaces['bubble'] == true,
    homeCardSurface: surfaces['home_card'] == true,
    modalSurface: surfaces['modal'] == true,
    bubbleIcon: _string(bubble['icon']) ?? 'megaphone',
    bubbleFrequency: _bubbleIntervals.containsKey(frequency)
        ? frequency as String
        : 'daily',
    bubbleMaxImpressions: maxImpressions is num && maxImpressions > 0
        ? maxImpressions.floor()
        : 5,
    audienceAuth: const <String>['all', 'guests', 'signed_in'].contains(auth)
        ? auth as String
        : 'all',
    title: value['title'] as String,
    summary: value['summary'] as String,
    body: _string(value['body']) ?? '',
    image: image is Map && imageUrl is String
        ? AnnouncementImage(
            url: imageUrl,
            thumbUrl: _string(image['thumb_url']),
            width: _int(image['width']),
            height: _int(image['height']),
            alt: _string(image['alt']) ?? '',
          )
        : null,
    steps: <AnnouncementStep>[
      for (final step in steps)
        if (step is Map && step['title'] is String)
          AnnouncementStep(
            title: step['title'] as String,
            text: _string(step['text']) ?? '',
            imageUrl: _string(step['image_url']),
            width: _int(step['width']),
            height: _int(step['height']),
          ),
    ],
    action: AnnouncementAction(
      type: _string(action['type']) ?? 'none',
      label: _string(action['label']) ?? '',
      webPath: safeSitePath(action['web_path']),
      // The app navigates by this route, so it follows the same-site rule.
      appRoute: safeSitePath(action['app_route']),
      externalUrl: safeSitePath(action['external_url']),
    ),
    version: _string(value['version']) ?? '',
    wave: _wave(value['wave']),
  );
}

List<Announcement> parseAnnouncements(Object? value) {
  if (value is! Map || value['results'] is! List) return const [];
  return <Announcement>[
    for (final item in value['results'] as List) ?_parseAnnouncement(item),
  ];
}

AnnouncementFeedPage parseAnnouncementFeed(Object? value) =>
    AnnouncementFeedPage(
      nextCursor: value is Map ? _string(value['next_cursor']) : null,
      results: parseAnnouncements(value),
    );

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in value.entries)
      if (entry.key is String &&
          _uuidPattern.hasMatch((entry.key as String).split(':').first) &&
          entry.value is String)
        entry.key as String: entry.value as String,
  };
}

AnnouncementLocalState parseLocalState(Object? value) {
  if (value is! Map) return const AnnouncementLocalState();
  final bubble = <String, BubbleSeen>{};
  final rawBubble = value['bubble'];
  if (rawBubble is Map) {
    for (final entry in rawBubble.entries) {
      final seen = entry.value;
      if (entry.key is String &&
          _uuidPattern.hasMatch(entry.key as String) &&
          seen is Map &&
          seen['shown'] is num &&
          seen['last'] is String) {
        bubble[entry.key as String] = BubbleSeen(
          shown: (seen['shown'] as num).toInt(),
          last: seen['last'] as String,
          wave: _wave(seen['wave']),
        );
      }
    }
  }
  final waves = <String, int>{};
  final rawWaves = value['waves'];
  if (rawWaves is Map) {
    for (final entry in rawWaves.entries) {
      if (entry.key is String && _uuidPattern.hasMatch(entry.key as String)) {
        waves[entry.key as String] = _wave(entry.value);
      }
    }
  }
  return AnnouncementLocalState(
    read: _stringMap(value['read']),
    dismissed: _stringMap(value['dismissed']),
    waves: waves,
    bubble: bubble,
    impressions: _stringMap(value['impressions']),
  );
}

List<Announcement> forAudience(List<Announcement> items, bool signedIn) => items
    .where(
      (item) =>
          item.audienceAuth == 'all' ||
          (item.audienceAuth == 'signed_in' ? signedIn : !signedIn),
    )
    .toList(growable: false);

/// The wave this device last read or closed it in; marks from before waves
/// count as 1.
int finishedWave(AnnouncementLocalState state, String id) =>
    state.waves[id] ??
    (state.read[id] != null || state.dismissed[id] != null ? 1 : 0);

/// Read or closed in the current wave: off the home screen, still in the feed.
bool isFinished(Announcement item, AnnouncementLocalState state) =>
    finishedWave(state, item.id) >= item.wave;

String _iso(DateTime value) => value.toUtc().toIso8601String();

/// Announcements the bubble carries now, by the admin's frequency and
/// impression limit.
List<Announcement> bubbleAnnouncements(
  List<Announcement> items,
  AnnouncementLocalState state,
  DateTime now,
  Set<String> shownThisSession,
) => items
    .where((item) {
      if (!item.bubbleSurface ||
          item.kind == 'fundraising' ||
          isFinished(item, state)) {
        return false;
      }
      if (shownThisSession.contains(item.id)) return true;
      final seen = state.bubble[item.id];
      if (seen == null || seen.wave < item.wave) return true;
      if (seen.shown >= item.bubbleMaxImpressions) return false;
      final last = DateTime.tryParse(seen.last);
      return last != null &&
          now.difference(last) >= _bubbleIntervals[item.bubbleFrequency]!;
    })
    .toList(growable: false);

AnnouncementLocalState recordBubbleShown(
  AnnouncementLocalState state,
  List<Announcement> items,
  DateTime now,
  Set<String> shownThisSession,
) {
  final bubble = <String, BubbleSeen>{...state.bubble};
  for (final item in items) {
    if (shownThisSession.contains(item.id)) continue;
    final seen = bubble[item.id];
    final shown = seen != null && seen.wave >= item.wave ? seen.shown : 0;
    bubble[item.id] = BubbleSeen(
      shown: shown + 1,
      last: _iso(now),
      wave: item.wave,
    );
  }
  return state.copyWith(bubble: bubble);
}

AnnouncementLocalState _finish(
  AnnouncementLocalState state, {
  required bool read,
  required String id,
  required DateTime now,
  required int wave,
}) {
  final marks = read ? state.read : state.dismissed;
  if (marks[id] != null && finishedWave(state, id) >= wave) return state;
  final next = <String, String>{...marks, id: marks[id] ?? _iso(now)};
  final waves = <String, int>{
    ...state.waves,
    id: finishedWave(state, id) > wave ? finishedWave(state, id) : wave,
  };
  return read
      ? state.copyWith(read: next, waves: waves)
      : state.copyWith(dismissed: next, waves: waves);
}

AnnouncementLocalState markRead(
  AnnouncementLocalState state,
  String id,
  DateTime now, [
  int wave = 1,
]) => _finish(state, read: true, id: id, now: now, wave: wave);

AnnouncementLocalState markDismissed(
  AnnouncementLocalState state,
  String id,
  DateTime now, [
  int wave = 1,
]) => _finish(state, read: false, id: id, now: now, wave: wave);

/// Server receipts of a signed-in person: marks only ever move forward.
AnnouncementLocalState mergeReceipts(
  AnnouncementLocalState state,
  Object? receipts,
) {
  if (receipts is! Map || receipts['results'] is! List) return state;
  final read = <String, String>{...state.read};
  final dismissed = <String, String>{...state.dismissed};
  final waves = <String, int>{...state.waves};
  for (final receipt in receipts['results'] as List) {
    if (receipt is! Map) continue;
    final id = receipt['announcement_id'];
    if (id is! String || !_uuidPattern.hasMatch(id)) continue;
    final readAt = receipt['read_at'];
    final dismissedAt = receipt['dismissed_at'];
    if (readAt is String || dismissedAt is String) {
      final previous = finishedWave(state, id);
      final current = _wave(receipt['wave']);
      waves[id] = previous > current ? previous : current;
    }
    if (readAt is String && read[id] == null) read[id] = readAt;
    if (dismissedAt is String && dismissed[id] == null) {
      dismissed[id] = dismissedAt;
    }
  }
  return state.copyWith(read: read, dismissed: dismissed, waves: waves);
}

/// One impression per announcement, surface and wave a day, decided on the
/// device.
({AnnouncementLocalState state, bool fresh}) takeImpression(
  AnnouncementLocalState state,
  String id,
  String surface,
  DateTime now, [
  int wave = 1,
]) {
  final key = '$id:$surface:$wave';
  final day = _iso(now).substring(0, 10);
  if (state.impressions[key] == day) return (state: state, fresh: false);
  return (
    state: state.copyWith(
      impressions: <String, String>{...state.impressions, key: day},
    ),
    fresh: true,
  );
}

class BodyBlock {
  const BodyBlock({required this.list, required this.lines});

  final bool list;
  final List<String> lines;

  @override
  bool operator ==(Object other) =>
      other is BodyBlock &&
      other.list == list &&
      other.lines.length == lines.length &&
      Iterable<int>.generate(
        lines.length,
      ).every((index) => other.lines[index] == lines[index]);

  @override
  int get hashCode => Object.hash(list, Object.hashAll(lines));

  @override
  String toString() => '${list ? 'list' : 'paragraph'}$lines';
}

/// The small Markdown subset admins write: paragraphs, "- " lists and
/// **bold**.
List<BodyBlock> bodyBlocks(String body) => body
    .split(RegExp(r'\n{2,}'))
    .map(
      (chunk) => chunk
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
    )
    .where((lines) => lines.isNotEmpty)
    .map(
      (lines) => lines.every((line) => line.trimLeft().startsWith('- '))
          ? BodyBlock(
              list: true,
              lines: lines
                  .map((line) => line.trimLeft().substring(2))
                  .toList(growable: false),
            )
          : BodyBlock(list: false, lines: lines),
    )
    .toList(growable: false);

typedef BoldSegment = ({String text, bool bold});

List<BoldSegment> boldSegments(String line) {
  final parts = <String>[];
  var start = 0;
  for (final match in RegExp(r'\*\*[^*]+\*\*').allMatches(line)) {
    parts
      ..add(line.substring(start, match.start))
      ..add(match.group(0)!);
    start = match.end;
  }
  parts.add(line.substring(start));
  return <BoldSegment>[
    for (final part in parts)
      if (part.isNotEmpty)
        part.startsWith('**') && part.endsWith('**') && part.length > 4
            ? (text: part.substring(2, part.length - 2), bold: true)
            : (text: part, bold: false),
  ];
}
