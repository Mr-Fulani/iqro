import 'package:flutter/widgets.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'audio_models.dart';
import 'listening_queue.dart';

String recitationStyleLabel(BuildContext context, String style) =>
    switch (style) {
      'murattal' => context.l10n.styleMurattal,
      'mujawwad' => context.l10n.styleMujawwad,
      'muallim' => context.l10n.styleMuallim,
      'kids-repeat' => context.l10n.styleKidsRepeat,
      _ => style,
    };

/// «Муратталь · Hafs 'an Asim»: the style and riwayah, as the site labels a
/// recording.
String recitationVariantLabel(BuildContext context, Recitation recitation) {
  final style = recitationStyleLabel(context, recitation.style);
  return recitation.riwayah.isEmpty ? style : '$style · ${recitation.riwayah}';
}

String queueModeLabel(BuildContext context, ListeningQueueMode mode) =>
    switch (mode) {
      ListeningQueueMode.stop => context.l10n.queueModeStop,
      ListeningQueueMode.next => context.l10n.queueModeNext,
      ListeningQueueMode.loop => context.l10n.queueModeLoop,
    };
