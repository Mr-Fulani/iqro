part of 'onboarding_screen.dart';

class _Header extends StatelessWidget {
  const _Header({
    required this.index,
    required this.total,
    required this.onBack,
    required this.onSkipTour,
  });

  final int index;
  final int total;
  final VoidCallback? onBack;
  final VoidCallback? onSkipTour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 0),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                if (onBack != null)
                  IconButton(
                    key: const Key('onboarding-back'),
                    tooltip: context.l10n.back,
                    onPressed: onBack,
                    icon: const BackButtonIcon(),
                  )
                else ...<Widget>[
                  const SizedBox(width: 12),
                  const IqroAnimatedLogo(size: 36),
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Text(
                      arabic ? 'إقرأ' : 'IQRO',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        letterSpacing: arabic ? 0 : 2,
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: onSkipTour == null
                        ? null
                        : TextButton(
                            key: const Key('onboarding-skip-tour'),
                            onPressed: onSkipTour,
                            child: Text(
                              context.l10n.onboardingSkipTour,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: context.l10n.onboardingStepOf(index + 1, total),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: List<Widget>.generate(total, (item) {
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: item <= index
                              ? theme.colorScheme.primary
                              : context.iqroColors.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (index, child) in children.indexed) ...<Widget>[
            if (index > 0) const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.icon, {this.strong = false});

  final IconData icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: strong ? scheme.primary : scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: IqroIcon(
          icon,
          size: 30,
          color: strong ? scheme.onPrimary : scheme.primary,
        ),
      ),
    );
  }
}

class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.title,
    required this.body,
    required this.child,
    this.top,
  });

  final Widget? top;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (top != null) ...<Widget>[top!, const SizedBox(height: 18)],
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onTap,
    required this.child,
    this.choiceKey,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final Key? choiceKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: IqroCard(
        key: choiceKey,
        onTap: onTap,
        color: selected ? scheme.primaryContainer : null,
        borderColor: selected ? scheme.primary : null,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: <Widget>[
              Expanded(child: child),
              if (selected) ...<Widget>[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, color: scheme.primary),
              ],
            ],
          ),
        ),
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
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _StepFrame(
      top: const _Badge(Icons.translate),
      title: l10n.onboardingWelcomeTitle,
      body: l10n.onboardingWelcomeBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroEyebrow(l10n.chooseLanguage),
          const SizedBox(height: 10),
          for (final (code, name, short) in _languages) ...<Widget>[
            _Choice(
              choiceKey: Key('onboarding-language-$code'),
              selected: selected == code,
              onTap: () => onSelected(code),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: selected == code
                        ? theme.colorScheme.primary
                        : context.iqroColors.panelSoft,
                    foregroundColor: selected == code
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    child: ExcludeSemantics(
                      child: Text(short, style: theme.textTheme.labelSmall),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      name,
                      textDirection: code == 'ar'
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (code == 'ar') ...<Widget>[
                    const SizedBox(width: 8),
                    Flexible(child: _Hint(l10n.onboardingRtl)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          _Hint(l10n.onboardingLanguageHint),
        ],
      ),
    );
  }
}

class _TourStep extends StatelessWidget {
  const _TourStep({
    required this.controller,
    required this.slide,
    required this.onSlide,
  });

  final PageController controller;
  final int slide;
  final ValueChanged<int> onSlide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final slides = <_TourSlideData>[
      _TourSlideData(
        Icons.menu_book_rounded,
        const <IconData>[
          Icons.translate,
          Icons.auto_stories_outlined,
          Icons.bookmark_outline,
        ],
        l10n.onboardingTourQuranTitle,
        <String>[
          l10n.onboardingTourQuran1,
          l10n.onboardingTourQuran2,
          l10n.onboardingTourQuran3,
        ],
      ),
      _TourSlideData(
        Icons.headphones_rounded,
        const <IconData>[
          Icons.graphic_eq,
          Icons.queue_music,
          Icons.download_for_offline_outlined,
        ],
        l10n.onboardingTourAudioTitle,
        <String>[
          l10n.onboardingTourAudio1,
          l10n.onboardingTourAudio2,
          l10n.onboardingTourAudio3,
        ],
      ),
      _TourSlideData(
        Icons.school_outlined,
        const <IconData>[
          Icons.track_changes_outlined,
          Icons.repeat,
          Icons.ondemand_video_outlined,
        ],
        l10n.onboardingTourStudyTitle,
        <String>[
          l10n.onboardingTourStudy1,
          l10n.onboardingTourStudy2,
          l10n.onboardingTourStudy3,
        ],
      ),
      _TourSlideData(
        iqroSalahIcon,
        const <IconData>[
          Icons.explore_outlined,
          Icons.calendar_month_outlined,
          iqroDuaIcon,
        ],
        l10n.onboardingTourDailyTitle,
        <String>[
          l10n.onboardingTourDaily1,
          l10n.onboardingTourDaily2,
          l10n.onboardingTourDaily3,
        ],
      ),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Expanded(
          child: PageView(
            controller: controller,
            onPageChanged: onSlide,
            children: <Widget>[for (final item in slides) _TourSlide(item)],
          ),
        ),
        Semantics(
          label: l10n.onboardingSlideOf(slide + 1, _tourSlides),
          liveRegion: true,
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_tourSlides, (index) {
                return AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  width: index == slide ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == slide
                        ? scheme.primary
                        : context.iqroColors.line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// IqroIcon only for the hand-drawn glyphs: it shows book icons as the brand
/// seal, which reads as a logo here.
Widget _glyph(IconData icon, double size, Color color) =>
    icon == iqroSalahIcon || icon == iqroDuaIcon
    ? IqroIcon(icon, size: size, color: color)
    : Icon(icon, size: size, color: color);

class _TourSlideData {
  const _TourSlideData(this.icon, this.extras, this.title, this.points);

  final IconData icon;
  final List<IconData> extras;
  final String title;
  final List<String> points;
}

class _TourSlide extends StatelessWidget {
  const _TourSlide(this.data);

  final _TourSlideData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExcludeSemantics(
            child: Container(
              height: 210,
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: _glyph(data.icon, 56, scheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (final icon in data.extras)
                        Container(
                          width: 44,
                          height: 44,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _glyph(icon, 24, context.iqroColors.gold),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Semantics(
            header: true,
            child: Text(data.title, style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 12),
          for (final point in data.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 8, end: 12),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.iqroColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(point, style: theme.textTheme.bodyLarge),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanStep extends StatelessWidget {
  const _PlanStep({
    required this.goal,
    required this.unit,
    required this.target,
    required this.onGoal,
    required this.onUnit,
    required this.onTarget,
  });

  final String goal;
  final DailyUnit unit;
  final int target;
  final ValueChanged<String> onGoal;
  final ValueChanged<DailyUnit> onUnit;
  final ValueChanged<int> onTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final goals = <(String, IconData, String)>[
      ('reading', Icons.menu_book_outlined, l10n.goalReading),
      ('memorization', Icons.repeat, l10n.goalMemorization),
      ('prayer', iqroSalahIcon, l10n.goalPrayer),
      ('dua', iqroDuaIcon, l10n.goalDua),
    ];
    final max = switch (unit) {
      DailyUnit.minutes => 60,
      DailyUnit.pages => 30,
      DailyUnit.ayahs => 50,
    };
    return _StepFrame(
      title: l10n.onboardingGoalTitle,
      body: l10n.onboardingGoalBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final (code, icon, label) in goals) ...<Widget>[
            _Choice(
              choiceKey: Key('onboarding-goal-$code'),
              selected: goal == code,
              onTap: () => onGoal(code),
              child: Row(
                children: <Widget>[
                  IqroIcon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          IqroEyebrow(l10n.onboardingDailyNorm),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<DailyUnit>(
              segments: <ButtonSegment<DailyUnit>>[
                ButtonSegment(
                  value: DailyUnit.minutes,
                  label: Text(l10n.minutes),
                ),
                ButtonSegment(value: DailyUnit.pages, label: Text(l10n.pages)),
                ButtonSegment(value: DailyUnit.ayahs, label: Text(l10n.ayahs)),
              ],
              selected: <DailyUnit>{unit},
              onSelectionChanged: (value) => onUnit(value.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 14),
          IqroCard(
            color: context.iqroColors.sand,
            borderColor: Colors.transparent,
            child: Column(
              children: <Widget>[
                Text(
                  _planAmount(l10n, unit, target),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                Slider(
                  value: target.clamp(1, max).toDouble(),
                  min: 1,
                  max: max.toDouble(),
                  divisions: max - 1,
                  label: '$target',
                  semanticFormatterCallback: (value) =>
                      _planAmount(l10n, unit, value.round()),
                  onChanged: (value) => onTarget(value.round()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Hint(l10n.guestNote),
        ],
      ),
    );
  }
}

class _PrayerStep extends StatelessWidget {
  const _PrayerStep({
    required this.setup,
    required this.methodCode,
    required this.asrMethod,
    required this.location,
    required this.locating,
    required this.error,
    required this.onUseLocation,
    required this.onChooseCity,
    required this.onMethod,
    required this.onAsr,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final OnboardingPrayerSetup? setup;
  final String? methodCode;
  final String asrMethod;
  final PrayerLocation? location;
  final bool locating;
  final Object? error;
  final VoidCallback onUseLocation;
  final VoidCallback onChooseCity;
  final ValueChanged<String> onMethod;
  final ValueChanged<String> onAsr;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final setup = this.setup;
    final methods = setup?.methods ?? const <PrayerMethod>[];
    final ready = methods.isNotEmpty && !locating;
    final city = prayerCityById(location?.cityId);
    final fromDevice = location != null && city == null;
    return _StepFrame(
      top: const _Badge(iqroSalahIcon),
      title: l10n.onboardingPrayerTitle,
      body: l10n.onboardingPrayerBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (setup == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (methods.isEmpty) ...<Widget>[
            IqroStatusBanner(
              icon: Icons.cloud_off_outlined,
              title: l10n.offline,
              message: l10n.onboardingPrayerOffline,
              color: context.iqroColors.sand,
            ),
          ] else ...<Widget>[
            _LocationOption(
              optionKey: const Key('onboarding-use-location'),
              icon: Icons.my_location_outlined,
              title: l10n.onboardingUseLocation,
              subtitle: l10n.onboardingUseLocationHint,
              selected: fromDevice,
              busy: locating,
              onTap: ready ? onUseLocation : null,
            ),
            const SizedBox(height: 10),
            _LocationOption(
              optionKey: const Key('onboarding-choose-city'),
              icon: Icons.search,
              title: l10n.onboardingChooseCity,
              subtitle: city?.nameFor(locale) ?? l10n.onboardingChooseCityHint,
              selected: city != null,
              busy: false,
              onTap: ready ? onChooseCity : null,
            ),
            if (location != null) ...<Widget>[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.onboardingLocationSelected(
                    city?.nameFor(locale) ?? l10n.currentLocation,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: 12),
              _LocationError(
                error: error!,
                onOpenLocationSettings: onOpenLocationSettings,
                onOpenAppSettings: onOpenAppSettings,
              ),
            ],
            const SizedBox(height: 22),
            IqroEyebrow(l10n.asrCalculation),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment(
                    value: 'standard',
                    label: Text(l10n.asrStandard),
                  ),
                  ButtonSegment(value: 'hanafi', label: Text(l10n.asrHanafi)),
                ],
                selected: <String>{asrMethod},
                onSelectionChanged: (value) => onAsr(value.single),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 8),
            _Hint(
              asrMethod == 'hanafi' ? l10n.asrHanafiHint : l10n.asrStandardHint,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: const Key('onboarding-method'),
              initialValue: methodCode,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.calculationMethod),
              items: methods
                  .map(
                    (method) => DropdownMenuItem<String>(
                      value: method.code,
                      child: Text(
                        method.nameFor(locale),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) onMethod(value);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationOption extends StatelessWidget {
  const _LocationOption({
    required this.optionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final Key optionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Choice(
      choiceKey: optionKey,
      selected: selected,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.primary,
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                _Hint(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationError extends StatelessWidget {
  const _LocationError({
    required this.error,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final Object error;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final code = error is ApiException ? (error as ApiException).code : null;
    final color = context.iqroColors.sand;
    return switch (code) {
      'location_disabled' => IqroStatusBanner(
        icon: Icons.location_off_outlined,
        title: l10n.locationServicesDisabled,
        message: l10n.locationServicesDisabledBody,
        actionLabel: l10n.settings,
        onAction: onOpenLocationSettings,
        color: color,
      ),
      'location_denied' => IqroStatusBanner(
        icon: Icons.location_disabled_outlined,
        title: l10n.locationPermissionRequired,
        message: l10n.locationPermissionRequiredBody,
        color: color,
      ),
      'location_denied_forever' => IqroStatusBanner(
        icon: Icons.location_disabled_outlined,
        title: l10n.locationPermissionRequired,
        message: l10n.locationDenied,
        actionLabel: l10n.settings,
        onAction: onOpenAppSettings,
        color: color,
      ),
      _ => IqroStatusBanner(
        icon: Icons.location_searching_outlined,
        title: l10n.locationUnavailable,
        message: l10n.prayerCalculationFailed,
        color: color,
      ),
    };
  }
}

class _RemindersStep extends StatelessWidget {
  const _RemindersStep({
    required this.remindPrayers,
    required this.permission,
    required this.blocked,
    required this.onRemindPrayers,
  });

  final bool remindPrayers;
  final ReminderPermission? permission;
  final bool blocked;
  final ValueChanged<bool> onRemindPrayers;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final names = <String>[
      l10n.fajr,
      l10n.dhuhr,
      l10n.asr,
      l10n.maghrib,
      l10n.isha,
    ].join(', ');
    return _StepFrame(
      top: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/brand/iqro-logo.png',
                    width: 36,
                    height: 36,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.dhuhr, style: theme.textTheme.titleSmall),
                      Text(
                        l10n.onboardingPreviewBody,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.notifications_active_outlined,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
      title: l10n.onboardingRemindersTitle,
      body: l10n.onboardingRemindersBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: SwitchListTile.adaptive(
              key: const Key('onboarding-five-prayers'),
              value: remindPrayers,
              onChanged: onRemindPrayers,
              title: Text(l10n.onboardingFivePrayers),
              subtitle: Text(names),
            ),
          ),
          if (permission == ReminderPermission.granted) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.onboardingNotificationsOn)),
              ],
            ),
          ] else if (blocked) ...<Widget>[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: IqroStatusBanner(
                icon: Icons.notifications_off_outlined,
                title: l10n.notificationAccess,
                message: l10n.onboardingNotificationsBlocked,
                color: context.iqroColors.sand,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExactRemindersStep extends StatelessWidget {
  const _ExactRemindersStep();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final steps = <String>[
      l10n.onboardingExactStep1,
      l10n.onboardingExactStep2,
      l10n.onboardingExactStep3,
    ];
    return _StepFrame(
      top: const _Badge(Icons.alarm_on_outlined),
      title: l10n.onboardingExactTitle,
      body: l10n.onboardingExactBody,
      child: IqroCard(
        child: Column(
          children: <Widget>[
            for (final (index, text) in steps.indexed)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                child: Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: context.iqroColors.sand,
                      foregroundColor: theme.colorScheme.onSurface,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(text, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsStep extends StatelessWidget {
  const _AnalyticsStep({required this.consent, required this.onPolicy});

  final AnalyticsConsent? consent;
  final VoidCallback onPolicy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    Widget row(IconData icon, Color color, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return _StepFrame(
      top: const _Badge(Icons.insights_outlined),
      title: l10n.analyticsTitle,
      body: l10n.analyticsCardText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroCard(
            child: Column(
              children: <Widget>[
                row(
                  Icons.check,
                  theme.colorScheme.primary,
                  l10n.onboardingAnalyticsCounts,
                ),
                row(
                  Icons.close,
                  theme.colorScheme.secondary,
                  l10n.onboardingAnalyticsNever,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onPolicy,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l10n.analyticsPolicy),
          ),
          if (consent != null) ...<Widget>[
            const SizedBox(height: 4),
            _Hint(
              consent == AnalyticsConsent.granted
                  ? l10n.analyticsStateGranted
                  : l10n.analyticsStateDenied,
            ),
          ],
        ],
      ),
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.rows});

  final List<(String, String, bool)> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return _StepFrame(
      top: const _Badge(Icons.check_rounded, strong: true),
      title: l10n.onboardingDoneTitle,
      body: l10n.onboardingDoneBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: <Widget>[
                for (final (index, (label, value, ok)) in rows.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  MergeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              value,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: ok ? null : theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // First launch: an account already on the phone signs in with one
          // tap. Hidden until Google sign-in is configured on the server.
          const GoogleSignInButton(
            trySilentSignIn: true,
            showSignedInAs: true,
            padding: EdgeInsets.only(bottom: 14),
          ),
          _Hint(l10n.onboardingDoneHint),
        ],
      ),
    );
  }
}
