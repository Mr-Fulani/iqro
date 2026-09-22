import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/local_database.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/audio_models.dart';
import '../audio/reciter_catalog.dart';
import '../audio/reciter_portraits.dart';
import '../quran/quran_models.dart';
import 'memorization_repository.dart';

class MemorizationScreen extends ConsumerWidget {
  const MemorizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionProvider);
    final ownerId = sessionState.isLoading
        ? null
        : sessionState.valueOrNull?.userId;
    final database = ref.watch(localDatabaseProvider);
    final currentScope = database.accountScope.current;
    final accountScope = currentScope?.userId == ownerId ? currentScope : null;
    final controller = ref.watch(memorizationProvider.notifier);
    return _MemorizationScreenBody(
      key: ValueKey<String>(
        '${accountScope?.userId ?? '<none>'}:${accountScope?.epoch ?? -1}',
      ),
      database: database,
      accountScope: accountScope,
      controller: controller,
    );
  }
}

class _MemorizationScreenBody extends ConsumerStatefulWidget {
  const _MemorizationScreenBody({
    required this.database,
    required this.accountScope,
    required this.controller,
    super.key,
  });

  final LocalDatabase database;
  final AccountScopeSnapshot? accountScope;
  final MemorizationController controller;

  @override
  ConsumerState<_MemorizationScreenBody> createState() =>
      _MemorizationScreenBodyState();
}

class _MemorizationScreenBodyState
    extends ConsumerState<_MemorizationScreenBody> {
  var _editing = false;
  var _saving = false;
  var _selectedSurah = 1;
  var _startAyah = 1;
  var _endAyah = 1;
  var _dailyRepetitions = 5;
  var _pauseSeconds = 2;
  String? _recitationId;
  var _requestGeneration = 0;
  var _audioExitRestoreRequested = false;

  @override
  void initState() {
    super.initState();
    _recitationId = ref
        .read(appPreferencesProvider)
        .memorizationDefaultRecitationId;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memorizationProvider);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _restoreAudioOnExit();
      },
      child: Scaffold(
        appBar: IqroTopBar(title: context.l10n.memorizationTitle),
        body: state.when(
          loading: () => const IqroLoading(),
          error: (error, stack) => IqroAsyncError(
            title: context.l10n.networkError,
            onRetry: _reload,
          ),
          data: _buildDashboard,
        ),
      ),
    );
  }

  Widget _buildDashboard(MemorizationDashboard dashboard) {
    final plan = dashboard.plan;
    final showEditor = _editing || plan == null;
    return IqroPage(
      child: Column(
        children: <Widget>[
          if (showEditor)
            _PlanEditor(
              selectedSurah: _selectedSurah,
              startAyah: _startAyah,
              endAyah: _endAyah,
              dailyRepetitions: _dailyRepetitions,
              pauseSeconds: _pauseSeconds,
              recitationId: _recitationId,
              saving: _saving,
              canCancel: plan != null,
              onSurahChanged: (value) => setState(() {
                _selectedSurah = value;
                _startAyah = 1;
                _endAyah = 1;
              }),
              onStartAyahChanged: (value) => setState(() {
                _startAyah = value;
                if (_endAyah < value) _endAyah = value;
              }),
              onEndAyahChanged: (value) => setState(() => _endAyah = value),
              onDailyRepetitionsChanged: (value) =>
                  setState(() => _dailyRepetitions = value),
              onPauseSecondsChanged: (value) =>
                  setState(() => _pauseSeconds = value),
              onRecitationChanged: (value) =>
                  setState(() => _recitationId = value),
              onSave: () => _savePlan(dashboard),
              onCancel: () => setState(() => _editing = false),
            )
          else
            _PracticeDashboard(
              dashboard: dashboard,
              saving: _saving,
              onEdit: () => _beginEditing(plan),
              onAssess: _assess,
              onReset: _confirmReset,
            ),
        ],
      ),
    );
  }

  void _beginEditing(MemorizationPlan plan) {
    setState(() {
      _selectedSurah = plan.startAyah.surah;
      _startAyah = plan.startAyah.ayah;
      _endAyah = plan.endAyah.ayah;
      _dailyRepetitions = plan.dailyRepetitions;
      _pauseSeconds = plan.pauseSeconds;
      _recitationId =
          plan.recitationId ??
          ref.read(appPreferencesProvider).memorizationDefaultRecitationId;
      _editing = true;
    });
  }

  Future<void> _savePlan(MemorizationDashboard dashboard) async {
    if (!_isCurrent() || _saving) return;
    final request = ++_requestGeneration;
    final ayahs = ref.read(ayahsProvider(_selectedSurah)).valueOrNull;
    final start = ayahs?.where((item) => item.number == _startAyah).firstOrNull;
    final end = ayahs?.where((item) => item.number == _endAyah).firstOrNull;
    if (start == null || end == null || end.number < start.number) {
      _showError(context.l10n.memorizationRangeInvalid);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.savePlan(
        MemorizationPlanDraft(
          startAyahId: start.id,
          endAyahId: end.id,
          recitationId: _recitationId,
          dailyRepetitions: _dailyRepetitions,
          pauseSeconds: _pauseSeconds,
        ),
        baseRevision: dashboard.plan?.revision ?? 0,
      );
      final selectedRecitationId = _recitationId?.trim();
      if (selectedRecitationId != null && selectedRecitationId.isNotEmpty) {
        await ref
            .read(appPreferencesProvider.notifier)
            .setMemorizationDefaultRecitation(selectedRecitationId);
      }
      if (!mounted) return;
      if (!_isCurrent(request)) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.memorizationPlanSaved)),
      );
    } on Object {
      if (mounted && _isCurrent(request)) {
        _showError(context.l10n.networkError);
      }
    } finally {
      if (_isCurrent(request)) setState(() => _saving = false);
    }
  }

  Future<void> _assess(MemorizationAssessment assessment) async {
    if (_saving || !_isCurrent()) return;
    final request = ++_requestGeneration;
    setState(() => _saving = true);
    try {
      await widget.controller.assess(assessment);
    } on Object {
      if (mounted && _isCurrent(request)) {
        _showError(context.l10n.networkError);
      }
    } finally {
      if (_isCurrent(request)) setState(() => _saving = false);
    }
  }

  Future<void> _confirmReset() async {
    if (_saving || !_isCurrent()) return;
    final request = ++_requestGeneration;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.resetToday),
        content: Text(context.l10n.resetConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.resetToday),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (!_isCurrent(request) || confirmed != true) return;
    setState(() => _saving = true);
    try {
      await widget.controller.reset();
    } on Object {
      if (mounted && _isCurrent(request)) {
        _showError(context.l10n.networkError);
      }
    } finally {
      if (_isCurrent(request)) setState(() => _saving = false);
    }
  }

  void _reload() {
    if (_isCurrent()) unawaited(widget.controller.reload());
  }

  bool _isCurrent([int? request]) {
    if (!mounted) return false;
    if (request != null && request != _requestGeneration) return false;
    final scope = widget.accountScope;
    if (scope == null || !widget.database.accountScope.isCurrent(scope)) {
      return false;
    }
    return identical(
      widget.controller,
      ref.read(memorizationProvider.notifier),
    );
  }

  void _restoreAudioOnExit() {
    if (_audioExitRestoreRequested) return;
    _audioExitRestoreRequested = true;
    final audioController = ref.read(audioControllerProvider.notifier);
    unawaited(
      audioController.restoreAudioAfterMemorization().catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    _restoreAudioOnExit();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PlanEditor extends ConsumerWidget {
  const _PlanEditor({
    required this.selectedSurah,
    required this.startAyah,
    required this.endAyah,
    required this.dailyRepetitions,
    required this.pauseSeconds,
    required this.recitationId,
    required this.saving,
    required this.canCancel,
    required this.onSurahChanged,
    required this.onStartAyahChanged,
    required this.onEndAyahChanged,
    required this.onDailyRepetitionsChanged,
    required this.onPauseSecondsChanged,
    required this.onRecitationChanged,
    required this.onSave,
    required this.onCancel,
  });

  final int selectedSurah;
  final int startAyah;
  final int endAyah;
  final int dailyRepetitions;
  final int pauseSeconds;
  final String? recitationId;
  final bool saving;
  final bool canCancel;
  final ValueChanged<int> onSurahChanged;
  final ValueChanged<int> onStartAyahChanged;
  final ValueChanged<int> onEndAyahChanged;
  final ValueChanged<int> onDailyRepetitionsChanged;
  final ValueChanged<int> onPauseSecondsChanged;
  final ValueChanged<String?> onRecitationChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(quranCatalogProvider);
    final ayahs = ref.watch(ayahsProvider(selectedSurah));
    final recitations = ref.watch(memorizationRecitationsProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final surahItems = catalog.valueOrNull?.surahs ?? const <Surah>[];
    final ayahItems = ayahs.valueOrNull ?? const <QuranAyah>[];
    final recitationItems = recitations.valueOrNull ?? const <Recitation>[];
    final activeRecitationId =
        recitationItems.any((item) => item.id == recitationId)
        ? recitationId!
        : '';
    return Column(
      children: <Widget>[
        IqroCard(
          color: context.iqroColors.ink,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                canCancel
                    ? context.l10n.memorizationEditPlan
                    : context.l10n.memorizationCreatePlan,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.memorizationPlanDescription,
                style: TextStyle(color: Colors.white.withValues(alpha: .72)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        IqroCard(
          child: Column(
            children: <Widget>[
              DropdownButtonFormField<int>(
                key: ValueKey<String>(
                  'surah-$selectedSurah-${surahItems.length}',
                ),
                initialValue:
                    surahItems.any((item) => item.number == selectedSurah)
                    ? selectedSurah
                    : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.l10n.surah),
                items: surahItems
                    .map(
                      (item) => DropdownMenuItem<int>(
                        value: item.number,
                        child: Text(
                          '${item.number}. ${item.nameFor(locale)} · ${item.nameAr}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) onSurahChanged(value);
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey<String>(
                        'start-$selectedSurah-$startAyah-${ayahItems.length}',
                      ),
                      initialValue:
                          ayahItems.any((item) => item.number == startAyah)
                          ? startAyah
                          : null,
                      decoration: InputDecoration(
                        labelText: context.l10n.startAyah,
                      ),
                      items: ayahItems
                          .map(
                            (item) => DropdownMenuItem<int>(
                              value: item.number,
                              child: Text('${item.number}'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value != null) onStartAyahChanged(value);
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey<String>(
                        'end-$selectedSurah-$endAyah-${ayahItems.length}',
                      ),
                      initialValue:
                          ayahItems.any((item) => item.number == endAyah)
                          ? endAyah
                          : null,
                      decoration: InputDecoration(
                        labelText: context.l10n.endAyah,
                      ),
                      items: ayahItems
                          .where((item) => item.number >= startAyah)
                          .map(
                            (item) => DropdownMenuItem<int>(
                              value: item.number,
                              child: Text('${item.number}'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value != null) onEndAyahChanged(value);
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _NumberSlider(
                label: context.l10n.memorizationDailyRepetitions,
                value: dailyRepetitions,
                min: 1,
                max: 100,
                enabled: !saving,
                onChanged: onDailyRepetitionsChanged,
              ),
              const SizedBox(height: 10),
              _NumberSlider(
                label: context.l10n.memorizationPauseSeconds,
                value: pauseSeconds,
                min: 0,
                max: 30,
                enabled: !saving,
                onChanged: onPauseSecondsChanged,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  'recitation-$activeRecitationId-${recitationItems.length}',
                ),
                initialValue: activeRecitationId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.memorizationReciter,
                ),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(context.l10n.memorizationWithoutAudio),
                  ),
                  ...recitationItems.map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        '${item.reciter.nameFor(locale)} · ${item.style}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) => onRecitationChanged(
                        value == null || value.isEmpty ? null : value,
                      ),
              ),
              if (catalog.isLoading || ayahs.isLoading || recitations.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: saving || ayahItems.isEmpty ? null : onSave,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(context.l10n.memorizationSavePlan),
                    ),
                  ),
                  if (canCancel) ...<Widget>[
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: saving ? null : onCancel,
                      child: Text(context.l10n.cancel),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberSlider extends StatelessWidget {
  const _NumberSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text('$value', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          onChanged: enabled ? (value) => onChanged(value.round()) : null,
        ),
      ],
    );
  }
}

class _PracticeDashboard extends ConsumerStatefulWidget {
  const _PracticeDashboard({
    required this.dashboard,
    required this.saving,
    required this.onEdit,
    required this.onAssess,
    required this.onReset,
  });

  final MemorizationDashboard dashboard;
  final bool saving;
  final VoidCallback onEdit;
  final ValueChanged<MemorizationAssessment> onAssess;
  final VoidCallback onReset;

  @override
  ConsumerState<_PracticeDashboard> createState() => _PracticeDashboardState();
}

class _PracticeDashboardState extends ConsumerState<_PracticeDashboard> {
  String? _audioLoadingKey;
  var _audioRequest = 0;

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final plan = dashboard.plan!;
    final locale = Localizations.localeOf(context).languageCode;
    final catalog = ref.watch(quranCatalogProvider).valueOrNull;
    final surah = catalog?.surahs
        .where((item) => item.number == plan.startAyah.surah)
        .firstOrNull;
    final ayahs = ref.watch(ayahsProvider(plan.startAyah.surah));
    final practiceAyahs = ayahs.valueOrNull
        ?.where(
          (item) =>
              item.number >= plan.startAyah.ayah &&
              item.number <= plan.endAyah.ayah,
        )
        .toList(growable: false);
    final completed = dashboard.today.completedRepetitions;
    final target = plan.dailyRepetitions;
    final progress = target == 0
        ? 0.0
        : (completed / target).clamp(0.0, 1.0).toDouble();
    final hasRecitation = plan.recitationId?.trim().isNotEmpty == true;
    final reciterLabel =
        plan.reciter?.nameFor(locale) ??
        (hasRecitation
            ? context.l10n.chooseReciter
            : context.l10n.memorizationWithoutAudio);
    final audio = ref.watch(
      audioControllerProvider.select(
        (state) => (
          track: state.track,
          channel: state.channel,
          playing: state.playing,
          rangeStartAyah: state.rangeStartAyah,
          rangeEndAyah: state.rangeEndAyah,
        ),
      ),
    );
    final rangeIsActive =
        hasRecitation &&
        audio.channel == AudioPlaybackChannel.memorization &&
        audio.track?.recitationId == plan.recitationId &&
        audio.track?.surah == plan.startAyah.surah &&
        audio.rangeStartAyah == plan.startAyah.ayah &&
        audio.rangeEndAyah == plan.endAyah.ayah;
    final rangeKey = _audioKey(plan.startAyah.ayah, plan.endAyah.ayah);
    final surahName =
        surah?.nameFor(locale) ??
        '${context.l10n.surah} ${plan.startAyah.surah}';
    final items = practiceAyahs ?? const <QuranAyah>[];

    return Column(
      children: <Widget>[
        IqroCard(
          color: context.iqroColors.ink,
          borderColor: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.iqroColors.gold.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: context.iqroColors.gold,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          surah?.nameAr ??
                              '${context.l10n.surah} ${plan.startAyah.surah}',
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontFamily: 'serif',
                                fontSize: 32,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${surah?.nameFor(locale) ?? '${context.l10n.surah} ${plan.startAyah.surah}'} · '
                          '${context.l10n.ayah} ${plan.startAyah.ayah}–${plan.endAyah.ayah}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: context.l10n.memorizationEditPlan,
                    onPressed: widget.saving ? null : widget.onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: widget.saving ? null : widget.onEdit,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: AlignmentDirectional.centerStart,
                  foregroundColor: Colors.white.withValues(alpha: .84),
                  disabledForegroundColor: Colors.white.withValues(alpha: .38),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.record_voice_over_outlined, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        reciterLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      dashboard.today.isCompleted
                          ? context.l10n.memorizationTodayCompleted
                          : '${context.l10n.memorizationRemaining}: '
                                '${dashboard.today.remainingRepetitions}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                  ),
                  Text(
                    '$completed / $target',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: .14),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      context.iqroColors.gold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: hasRecitation
                    ? FilledButton.icon(
                        onPressed: widget.saving || _audioLoadingKey != null
                            ? null
                            : () => _playRange(
                                plan: plan,
                                surahName: surahName,
                                startAyah: plan.startAyah.ayah,
                                endAyah: plan.endAyah.ayah,
                              ),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.iqroColors.gold,
                          foregroundColor: context.iqroColors.ink,
                        ),
                        icon: _audioLoadingKey == rangeKey
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                audio.playing && rangeIsActive
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                        label: Text(
                          audio.playing && rangeIsActive
                              ? context.l10n.pause
                              : context.l10n.play,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: widget.saving ? null : widget.onEdit,
                        style: TextButton.styleFrom(
                          foregroundColor: context.iqroColors.gold,
                        ),
                        icon: const Icon(Icons.volume_off_outlined),
                        label: Text(context.l10n.memorizationReciter),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        IqroCard(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: ayahs.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Text(context.l10n.noQuranData),
            data: (_) => items.isEmpty
                ? Text(context.l10n.noQuranData)
                : Column(
                    children: <Widget>[
                      for (
                        var index = 0;
                        index < items.length;
                        index++
                      ) ...<Widget>[
                        _buildAyahRow(
                          context: context,
                          ayah: items[index],
                          plan: plan,
                          surahName: surahName,
                          player: audio,
                        ),
                        if (index < items.length - 1) const Divider(height: 20),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        IqroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.repetitionTarget,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.saving
                          ? null
                          : () =>
                                widget.onAssess(MemorizationAssessment.repeat),
                      child: Text(context.l10n.again),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.saving
                          ? null
                          : () => widget.onAssess(
                              MemorizationAssessment.difficult,
                            ),
                      child: Text(context.l10n.hard),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.saving
                          ? null
                          : () => widget.onAssess(
                              MemorizationAssessment.memorized,
                            ),
                      child: Text(context.l10n.good),
                    ),
                  ),
                ],
              ),
              if (widget.saving) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: widget.saving || completed == 0 ? null : widget.onReset,
          icon: const Icon(Icons.restart_alt),
          label: Text(context.l10n.resetToday),
        ),
      ],
    );
  }

  Widget _buildAyahRow({
    required BuildContext context,
    required QuranAyah ayah,
    required MemorizationPlan plan,
    required String surahName,
    required ({
      AudioTrack? track,
      bool playing,
      int? rangeStartAyah,
      int? rangeEndAyah,
      AudioPlaybackChannel channel,
    })
    player,
  }) {
    final hasRecitation = plan.recitationId?.trim().isNotEmpty == true;
    final rangeKey = _audioKey(ayah.number, ayah.number);
    final isActive =
        hasRecitation &&
        player.channel == AudioPlaybackChannel.memorization &&
        player.track?.recitationId == plan.recitationId &&
        player.track?.surah == ayah.surahNumber &&
        player.rangeStartAyah == ayah.number &&
        player.rangeEndAyah == ayah.number;
    final loading = _audioLoadingKey == rangeKey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              '${ayah.textUthmani}  ﴿${ayah.number}﴾',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'serif',
                height: 1.8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: hasRecitation
                ? (isActive && player.playing
                      ? context.l10n.pause
                      : context.l10n.play)
                : context.l10n.chooseReciter,
            onPressed: widget.saving
                ? null
                : hasRecitation
                ? () => _playRange(
                    plan: plan,
                    surahName: surahName,
                    startAyah: ayah.number,
                    endAyah: ayah.number,
                  )
                : widget.onEdit,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isActive && player.playing
                        ? Icons.pause_rounded
                        : hasRecitation
                        ? Icons.play_arrow_rounded
                        : Icons.record_voice_over_outlined,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _playRange({
    required MemorizationPlan plan,
    required String surahName,
    required int startAyah,
    required int endAyah,
  }) async {
    final selectedRecitationId = plan.recitationId?.trim();
    if (selectedRecitationId == null || selectedRecitationId.isEmpty) {
      widget.onEdit();
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final current = ref.read(audioControllerProvider);
    final isActive =
        current.channel == AudioPlaybackChannel.memorization &&
        current.track?.recitationId == selectedRecitationId &&
        current.track?.surah == plan.startAyah.surah &&
        current.rangeStartAyah == startAyah &&
        current.rangeEndAyah == endAyah;
    if (isActive) {
      await controller.toggle();
      return;
    }

    final request = ++_audioRequest;
    final key = _audioKey(startAyah, endAyah);
    setState(() => _audioLoadingKey = key);
    try {
      final recitations = await ref.read(
        memorizationRecitationsProvider.future,
      );
      final recitation =
          recitations
              .where((item) => item.id == selectedRecitationId)
              .firstOrNull ??
          preferredRecitation(
            recitations,
            preferredId: selectedRecitationId,
            role: AudioRecitationRole.memorization,
          );
      if (recitation == null) throw const FormatException('no recitation');
      final playback = await ref
          .read(audioRepositoryProvider)
          .playback(recitationId: recitation.id, surah: plan.startAyah.surah);
      if (!mounted || request != _audioRequest) return;
      final apiBaseUrl = ref.read(appConfigProvider).apiBaseUrl;
      await controller.loadPlayback(
        playback: playback,
        reciter: reciterWithPersonPortrait(
          recitation.reciter,
          apiBaseUrl: apiBaseUrl,
          reciters: recitations.map((item) => item.reciter),
        ),
        channel: AudioPlaybackChannel.memorization,
        surahName: surahName,
        startAyah: startAyah,
        endAyah: endAyah,
      );
    } on Object {
      if (mounted && request == _audioRequest) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
      }
    } finally {
      if (mounted && request == _audioRequest) {
        setState(() => _audioLoadingKey = null);
      }
    }
  }

  String _audioKey(int startAyah, int endAyah) => '$startAyah:$endAyah';

  @override
  void dispose() {
    _audioRequest += 1;
    super.dispose();
  }
}
