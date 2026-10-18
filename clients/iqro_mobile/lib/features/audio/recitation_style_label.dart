import 'package:flutter/widgets.dart';

import '../../core/design_system/iqro_widgets.dart';

String recitationStyleLabel(BuildContext context, String style) =>
    switch (style) {
      'murattal' => context.l10n.styleMurattal,
      'mujawwad' => context.l10n.styleMujawwad,
      'muallim' => context.l10n.styleMuallim,
      'kids-repeat' => context.l10n.styleKidsRepeat,
      _ => style,
    };
