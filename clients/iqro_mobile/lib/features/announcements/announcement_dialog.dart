import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'announcement_controller.dart';
import 'announcement_logic.dart';
import 'announcement_parts.dart';

/// Opens the window of one or several announcements. From the bubble it grows
/// out of the bubble, at [origin] on the screen.
Future<void> showAnnouncementDialog(
  BuildContext context, {
  required List<Announcement> items,
  required String surface,
  Offset? origin,
}) {
  final router = GoRouter.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.close,
    barrierColor: const Color(0x730F172A),
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 360),
    pageBuilder: (context, animation, secondaryAnimation) =>
        AnnouncementDialog(items: items, surface: surface, router: router),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (surface != 'bubble') {
        return FadeTransition(opacity: animation, child: child);
      }
      final grow = CurvedAnimation(
        parent: animation,
        curve: const Cubic(.2, .9, .25, 1.08),
        reverseCurve: Curves.easeIn,
      );
      final size = MediaQuery.sizeOf(context);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .08, end: 1).animate(grow),
          alignment: origin == null || size.isEmpty
              ? AlignmentDirectional.topEnd.resolve(Directionality.of(context))
              : Alignment(
                  origin.dx / size.width * 2 - 1,
                  origin.dy / size.height * 2 - 1,
                ),
          child: child,
        ),
      );
    },
  );
}

class AnnouncementDialog extends ConsumerStatefulWidget {
  const AnnouncementDialog({
    required this.items,
    required this.surface,
    required this.router,
    super.key,
  });

  final List<Announcement> items;
  final String surface;
  final GoRouter router;

  @override
  ConsumerState<AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends ConsumerState<AnnouncementDialog> {
  var _page = 0;
  var _forward = true;

  Announcement get _item => widget.items[_page];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _opened());
  }

  // Seeing a page reads it: it leaves the bubble and the feed's dot goes out.
  void _opened() {
    if (!mounted) return;
    ref
        .read(announcementsProvider.notifier)
        .read(_item, widget.surface, opened: true);
  }

  void _go(int delta) {
    final next = (_page + delta).clamp(0, widget.items.length - 1);
    if (next == _page) return;
    setState(() {
      _forward = next > _page;
      _page = next;
    });
    _opened();
  }

  Future<void> _act() async {
    final item = _item;
    if (item.action.appRoute != null) Navigator.of(context).pop();
    await openAnnouncementAction(ref, widget.router, item, widget.surface);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.items.length;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final heading = count > 1
        ? '${context.l10n.newsTitle} · '
              '${context.l10n.newsCounter(_page + 1, count)}'
        : context.l10n.newsTitle;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 64, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height * .86,
            ),
            child: DecoratedBox(
              // The site's shadow: soft, below the window.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 48,
                    spreadRadius: -12,
                    offset: Offset(0, 24),
                  ),
                ],
              ),
              child: Material(
                key: const ValueKey('announcement-dialog'),
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: heading,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  heading,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('announcement-close'),
                              style: IconButton.styleFrom(
                                backgroundColor: context.iqroColors.panelSoft,
                                foregroundColor: theme.colorScheme.onSurface,
                              ),
                              tooltip: context.l10n.close,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragEnd: count < 2
                                ? null
                                : (details) {
                                    final velocity =
                                        details.primaryVelocity ?? 0;
                                    if (velocity.abs() < 200) return;
                                    // Swiping toward the start of the line
                                    // turns to the next page.
                                    final leftward = velocity < 0;
                                    _go(leftward != rtl ? 1 : -1);
                                  },
                            child: AnimatedSwitcher(
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              transitionBuilder: (child, animation) {
                                final incoming =
                                    child.key == ValueKey(_item.id);
                                final from =
                                    (_forward == incoming ? 1 : -1) *
                                    (rtl ? -.2 : .2);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: Offset(from, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: _AnnouncementPage(
                                key: ValueKey(_item.id),
                                item: _item,
                                onAction: announcementHasAction(_item)
                                    ? _act
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        if (count > 1)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              top: 14,
                              end: 8,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: ExcludeSemantics(
                                    child: Wrap(
                                      spacing: 6,
                                      children: <Widget>[
                                        for (
                                          var index = 0;
                                          index < count;
                                          index++
                                        )
                                          AnimatedContainer(
                                            duration: reduced
                                                ? Duration.zero
                                                : const Duration(
                                                    milliseconds: 200,
                                                  ),
                                            width: index == _page ? 22 : 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: index == _page
                                                  ? theme.colorScheme.primary
                                                  : theme.colorScheme.outline,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton.outlined(
                                  key: const ValueKey('announcement-previous'),
                                  tooltip: context.l10n.newsPrevious,
                                  onPressed: _page == 0 ? null : () => _go(-1),
                                  icon: const Icon(Icons.chevron_left_rounded),
                                ),
                                const SizedBox(width: 8),
                                IconButton.outlined(
                                  key: const ValueKey('announcement-next'),
                                  tooltip: context.l10n.newsNext,
                                  onPressed: _page == count - 1
                                      ? null
                                      : () => _go(1),
                                  icon: const Icon(Icons.chevron_right_rounded),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementPage extends StatelessWidget {
  const _AnnouncementPage({required this.item, this.onAction, super.key});

  final Announcement item;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final label = item.action.label.isNotEmpty
        ? item.action.label
        : context.l10n.newsMore;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(end: 8, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          AnnouncementPicture(item: item, size: item.image != null ? 96 : 64),
          const SizedBox(height: 14),
          IqroEyebrow(announcementKindLabel(context, item.kind)),
          Semantics(
            header: true,
            child: Text(
              item.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.summary,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          if (item.body.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            AnnouncementBody(body: item.body),
          ],
          if (item.steps.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            for (final (index, step) in item.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${index + 1}.',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (step.imageUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AspectRatio(
                                  aspectRatio:
                                      step.width != null &&
                                          step.height != null &&
                                          step.height! > 0
                                      ? step.width! / step.height!
                                      : 16 / 9,
                                  child: AnnouncementNetworkImage(
                                    url: step.imageUrl!,
                                    fallback: ColoredBox(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Text(step.title, style: theme.textTheme.titleSmall),
                          if (step.text.isNotEmpty)
                            Text(
                              step.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            announcementDate(context, item),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          if (onAction != null) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('announcement-action'),
                onPressed: onAction,
                icon: Icon(
                  item.action.appRoute != null
                      ? (item.action.type == 'reciter'
                            ? Icons.play_arrow_rounded
                            : Icons.arrow_forward_rounded)
                      : Icons.open_in_new_rounded,
                ),
                label: Text(label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
