import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/widgets/home_widget_pinning.dart';
import '../plan/plan_repository.dart';

/// Both home screen widgets in one place. The Prayer and Plan screens keep
/// their own buttons; this is where people look for widgets.
class HomeWidgetsSettingsCard extends ConsumerStatefulWidget {
  const HomeWidgetsSettingsCard({super.key});

  @override
  ConsumerState<HomeWidgetsSettingsCard> createState() =>
      _HomeWidgetsSettingsCardState();
}

class _HomeWidgetsSettingsCardState
    extends ConsumerState<HomeWidgetsSettingsCard> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    // Keeps today's plan loaded for the Plan widget's snapshot.
    final plan = ref.watch(planProvider).valueOrNull;
    final add = Icon(
      Icons.add_circle_outline,
      color: Theme.of(context).colorScheme.primary,
    );
    return IqroCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: <Widget>[
          IqroListTile(
            key: const Key('settings-widget-prayer'),
            icon: Icons.mosque_outlined,
            title: context.l10n.prayerWidget,
            subtitle: context.l10n.prayerWidgetHint,
            trailing: add,
            onTap: _busy ? null : () => _run(_addPrayerWidget),
          ),
          const Divider(height: 1),
          IqroListTile(
            key: const Key('settings-widget-plan'),
            icon: Icons.track_changes_outlined,
            title: context.l10n.planWidget,
            subtitle: context.l10n.planWidgetHint,
            trailing: add,
            onTap: _busy || plan == null
                ? null
                : () => _run(() => _addPlanWidget(plan)),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AccountScopeChanged {
      // The new account publishes its own widget data.
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'IQRO home widgets',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPrayerWidget() async {
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    final service = ref.read(prayerWidgetServiceProvider);
    var hasSchedule = false;
    if (scope != null) {
      final result = await service.update(
        locale: Localizations.localeOf(context).languageCode,
        accountScope: scope,
      );
      database.ensureCurrent(scope);
      hasSchedule = result.hasSchedule;
    }
    if (!mounted) return;
    if (!hasSchedule) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.prayerWidgetNeedsLocation)),
      );
      return;
    }
    await _showPinResult(await service.requestPin());
  }

  Future<void> _addPlanWidget(DailyPlan plan) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !ref.read(planProvider.notifier).isBoundTo(scope)) {
      throw const AccountScopeChanged();
    }
    final service = ref.read(planWidgetServiceProvider);
    await service.update(
      plan: plan,
      locale: Localizations.localeOf(context).languageCode,
      accountScope: scope,
    );
    await _showPinResult(await service.requestPin());
  }

  Future<void> _showPinResult(HomeWidgetPinResult result) async {
    if (!mounted) return;
    if (result != HomeWidgetPinResult.unsupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == HomeWidgetPinResult.alreadyInstalled
                ? context.l10n.homeWidgetAlreadyAdded
                : context.l10n.prayerWidgetPinRequested,
          ),
        ),
      );
      return;
    }
    // Launchers without pinning, and iOS: say where widgets are added.
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          defaultTargetPlatform == TargetPlatform.iOS
              ? context.l10n.prayerWidgetManualIos
              : context.l10n.prayerWidgetManualAndroid,
        ),
      ),
    );
  }
}
