import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'palm_growth.dart';

/// Gold of the progress bar, as in the home-screen widget.
const palmGold = Color(0xFFEBC776);

/// The photograph of a stage, used as the Plan card's background.
String palmStageAsset(PalmStage stage) =>
    'assets/plan/palm_stage_${stage.index}.webp';

/// A square crop of the stage that keeps the plant readable when small.
String palmThumbAsset(PalmStage stage) =>
    'assets/plan/palm_thumb_${stage.index}.webp';

/// A resting palm keeps its growth; the photograph only softens its colour.
const _restingFilter = ColorFilter.matrix(<double>[
  0.70, 0.25, 0.05, 0, 0, //
  0.15, 0.80, 0.05, 0, 0,
  0.15, 0.25, 0.60, 0, 0,
  0, 0, 0, 1, 0,
]);

Widget _moodTint(PalmMood mood, Widget child) => mood == PalmMood.resting
    ? ColorFiltered(colorFilter: _restingFilter, child: child)
    : child;

/// The palm as a round photograph, for compact places such as Home.
class PalmGrowthArt extends StatelessWidget {
  const PalmGrowthArt({
    required this.stage,
    required this.mood,
    this.size = 96,
    super.key,
  });

  final PalmStage stage;
  final PalmMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: _moodTint(
        mood,
        Image.asset(
          palmThumbAsset(stage),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

/// Plan tab card: the stage's photograph as the background, the stage and
/// the way to the next one. The explanation waits behind the info button.
/// A new stage fades in and a tap makes the scene breathe; reduced motion
/// keeps it still.
class PalmGrowthCard extends StatefulWidget {
  const PalmGrowthCard({required this.growth, super.key});

  final PalmGrowth growth;

  @override
  State<PalmGrowthCard> createState() => _PalmGrowthCardState();
}

class _PalmGrowthCardState extends State<PalmGrowthCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _touch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _touchScale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1,
            end: 1.06,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 35,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1.06,
            end: 1,
          ).chain(CurveTween(curve: Curves.elasticOut)),
          weight: 65,
        ),
      ]).animate(_touch);

  @override
  void dispose() {
    _touch.dispose();
    super.dispose();
  }

  void _respond() {
    unawaited(HapticFeedback.lightImpact());
    if (MediaQuery.disableAnimationsOf(context)) return;
    unawaited(_touch.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final growth = widget.growth;
    final next = growth.nextStage;
    final stageLabel = palmStageLabel(l10n, growth.stage);
    const onImage = Colors.white;
    return Semantics(
      container: true,
      label: stageLabel,
      child: Card(
        key: const ValueKey('palm-growth'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: InkWell(
          onTap: _respond,
          child: ConstrainedBox(
            // At least the photograph's band; larger text makes it taller.
            constraints: const BoxConstraints(minHeight: 196),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _touchScale,
                    builder: (context, child) => Transform.scale(
                      key: const ValueKey('palm-scene'),
                      // A short breath when touched.
                      scale: _touchScale.value,
                      alignment: const Alignment(.55, .4),
                      child: child,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: <Widget>[...previous, ?current],
                      ),
                      child: _moodTint(
                        growth.mood,
                        Image.asset(
                          palmStageAsset(growth.stage),
                          key: ValueKey(growth.stage),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ),
                ),
                // Shade on the text side so white reads on bright sky.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[Color(0xB3231B0E), Color(0x00231B0E)],
                        stops: <double>[.15, .75],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              stageLabel,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: onImage,
                                fontWeight: FontWeight.w600,
                                shadows: const <Shadow>[
                                  Shadow(blurRadius: 8, color: Colors.black45),
                                ],
                              ),
                            ),
                          ),
                          Tooltip(
                            key: const ValueKey('palm-info'),
                            triggerMode: TooltipTriggerMode.tap,
                            showDuration: const Duration(seconds: 8),
                            preferBelow: true,
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            message:
                                '${palmMoodLabel(l10n, growth.mood)}\n\n'
                                '${l10n.palmHowItGrows}',
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.info_outline_rounded,
                                color: onImage,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 88),
                      SizedBox(
                        width: 190,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              next == null
                                  ? l10n.palmFullyGrown
                                  : l10n.palmNextStage(
                                      palmStageLabel(l10n, next),
                                    ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: onImage,
                              ),
                            ),
                            if (next != null) ...<Widget>[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: growth.progressToNext,
                                minHeight: 6,
                                color: palmGold,
                                backgroundColor: Colors.white24,
                                borderRadius: BorderRadius.circular(4),
                                semanticsLabel: l10n.palmNextStage(
                                  palmStageLabel(l10n, next),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
