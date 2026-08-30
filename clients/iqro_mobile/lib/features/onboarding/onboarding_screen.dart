import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  var _page = 0;
  var _goal = 'reading';
  var _unit = DailyUnit.pages;
  var _target = 6;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < 2) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final preferences = ref.read(appPreferencesProvider);
    await ref
        .read(appPreferencesProvider.notifier)
        .completeOnboarding(
          locale: preferences.locale,
          goal: _goal,
          unit: _unit,
          target: _target,
        );
    if (mounted) context.go('/app');
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 4),
              child: Row(
                children: <Widget>[
                  _Logo(locale: preferences.locale),
                  const Spacer(),
                  Text(
                    '${_page + 1} / 3',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) => setState(() => _page = value),
                children: <Widget>[
                  _LanguageStep(
                    selected: preferences.locale,
                    onSelected: (value) {
                      ref
                          .read(appPreferencesProvider.notifier)
                          .setLocale(value);
                    },
                  ),
                  _GoalStep(
                    selected: _goal,
                    onSelected: (value) => setState(() => _goal = value),
                  ),
                  _NormStep(
                    unit: _unit,
                    target: _target,
                    onUnit: (value) => setState(() {
                      _unit = value;
                      _target = switch (value) {
                        DailyUnit.minutes => 10,
                        DailyUnit.pages => 6,
                        DailyUnit.ayahs => 10,
                      };
                    }),
                    onTarget: (value) => setState(() => _target = value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                20,
                12,
                20,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(3, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: index == _page ? 28 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: index == _page
                              ? Theme.of(context).colorScheme.primary
                              : context.iqroColors.line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _next,
                      icon: Icon(
                        _page == 2
                            ? Icons.shield_outlined
                            : Icons.arrow_forward,
                      ),
                      label: Text(
                        _page == 2
                            ? context.l10n.startAsGuest
                            : context.l10n.continueLabel,
                      ),
                    ),
                  ),
                  if (_page == 2) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.guestNote,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.locale});
  final String locale;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.iqroColors.ink,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'اق',
            textDirection: TextDirection.rtl,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          locale == 'ar' ? 'إقرأ' : 'IQRO',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: locale == 'ar' ? 0 : 2,
          ),
        ),
      ],
    );
  }
}

class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.icon,
    required this.title,
    required this.body,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 10),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const languages = <(String, String, String)>[
      ('ru', 'Русский', 'RU'),
      ('en', 'English', 'EN'),
      ('ar', 'العربية', 'عر'),
      ('tr', 'Türkçe', 'TR'),
    ];
    return _StepFrame(
      icon: Icons.translate,
      title: context.l10n.welcomeTitle,
      body: context.l10n.welcomeBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroEyebrow(context.l10n.chooseLanguage),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: languages
                .map((item) {
                  final active = selected == item.$1;
                  return Semantics(
                    selected: active,
                    button: true,
                    child: IqroCard(
                      onTap: () => onSelected(item.$1),
                      color: active
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderColor: active
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: active
                                ? Theme.of(context).colorScheme.primary
                                : context.iqroColors.panelSoft,
                            foregroundColor: active
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            child: Text(
                              item.$3,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              item.$2,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final goals = <(String, IconData, String)>[
      ('reading', Icons.menu_book_outlined, context.l10n.goalReading),
      ('memorization', Icons.repeat, context.l10n.goalMemorization),
      ('prayer', Icons.mosque_outlined, context.l10n.goalPrayer),
      ('dua', Icons.auto_awesome_outlined, context.l10n.goalDua),
    ];
    return _StepFrame(
      icon: Icons.explore_outlined,
      title: context.l10n.chooseGoal,
      body: context.l10n.welcomeBody,
      child: Column(
        children: goals
            .map((goal) {
              final active = goal.$1 == selected;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: IqroCard(
                  onTap: () => onSelected(goal.$1),
                  color: active
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  borderColor: active
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        goal.$2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          goal.$3,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Icon(active ? Icons.check_circle : Icons.circle_outlined),
                    ],
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _NormStep extends StatelessWidget {
  const _NormStep({
    required this.unit,
    required this.target,
    required this.onUnit,
    required this.onTarget,
  });
  final DailyUnit unit;
  final int target;
  final ValueChanged<DailyUnit> onUnit;
  final ValueChanged<int> onTarget;

  @override
  Widget build(BuildContext context) {
    final max = switch (unit) {
      DailyUnit.minutes => 60,
      DailyUnit.pages => 30,
      DailyUnit.ayahs => 50,
    };
    final label = switch (unit) {
      DailyUnit.minutes => context.l10n.minutes,
      DailyUnit.pages => context.l10n.pages,
      DailyUnit.ayahs => context.l10n.ayahs,
    };
    return _StepFrame(
      icon: Icons.track_changes_outlined,
      title: context.l10n.dailyNorm,
      body: context.l10n.guestNote,
      child: Column(
        children: <Widget>[
          SegmentedButton<DailyUnit>(
            segments: <ButtonSegment<DailyUnit>>[
              ButtonSegment(
                value: DailyUnit.minutes,
                label: Text(context.l10n.minutes),
              ),
              ButtonSegment(
                value: DailyUnit.pages,
                label: Text(context.l10n.pages),
              ),
              ButtonSegment(
                value: DailyUnit.ayahs,
                label: Text(context.l10n.ayahs),
              ),
            ],
            selected: <DailyUnit>{unit},
            onSelectionChanged: (value) => onUnit(value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 28),
          IqroCard(
            color: context.iqroColors.sand,
            borderColor: Colors.transparent,
            child: Column(
              children: <Widget>[
                Text(
                  '$target',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text(label),
                Slider(
                  value: target.toDouble(),
                  min: 1,
                  max: max.toDouble(),
                  divisions: max - 1,
                  label: '$target',
                  onChanged: (value) => onTarget(value.round()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
