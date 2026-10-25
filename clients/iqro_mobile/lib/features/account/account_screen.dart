import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/auth/account_scope.dart';
import '../../core/auth/auth_session.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_error_text.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/iqro_theme.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionProvider);
    if (sessionState.isLoading) {
      return Scaffold(
        appBar: IqroTopBar(title: context.l10n.personalProfile),
        body: const IqroLoading(),
      );
    }
    final session = sessionState.valueOrNull;
    final database = ref.watch(localDatabaseProvider);
    final currentScope = database.accountScope.current;
    final accountScope = currentScope?.userId == session?.userId
        ? currentScope
        : null;
    final controller = ref.watch(sessionProvider.notifier);
    return _AccountScreenBody(
      key: ValueKey<String>(
        '${accountScope?.userId ?? '<none>'}:'
        '${accountScope?.epoch ?? -1}:${session?.isVerified == true}',
      ),
      database: database,
      accountScope: accountScope,
      controller: controller,
    );
  }
}

class _AccountScreenBody extends ConsumerStatefulWidget {
  const _AccountScreenBody({
    required this.database,
    required this.accountScope,
    required this.controller,
    super.key,
  });

  final LocalDatabase database;
  final AccountScopeSnapshot? accountScope;
  final SessionController controller;

  @override
  ConsumerState<_AccountScreenBody> createState() => _AccountScreenBodyState();
}

class _AccountScreenBodyState extends ConsumerState<_AccountScreenBody> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  EmailChallenge? _challenge;
  String? _emailError;
  String? _message;
  var _working = false;
  var _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider).valueOrNull;
    if (session != null && (session.isVerified || session.isPendingDeletion)) {
      // Picks up a deletion scheduled or cancelled on another device.
      unawaited(widget.controller.refreshAccountStatus());
    }
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    _emailController.clear();
    _codeController.clear();
    _challenge = null;
    _emailError = null;
    _message = null;
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncProvider);
    final current = session.valueOrNull;
    final verified = current?.isVerified == true;
    final pendingDeletion = current?.isPendingDeletion == true;
    final signedIn = verified || (pendingDeletion && current?.email != null);
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.personalProfile),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IqroCard(
              color: signedIn
                  ? Theme.of(context).colorScheme.primaryContainer
                  : context.iqroColors.lavender,
              borderColor: Colors.transparent,
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    child: Icon(
                      signedIn ? Icons.person : Icons.shield_outlined,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          signedIn
                              ? current!.email!
                              : context.l10n.readingAsGuest,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          signedIn
                              ? context.l10n.personalProfile
                              : context.l10n.guestSyncHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (pendingDeletion)
              _pendingDeletionCard(context, current!)
            else if (!verified)
              _signInCard(context)
            else ...<Widget>[
              _verifiedActions(context, current!),
              const SizedBox(height: 16),
              _deletionCard(context, current),
            ],
            // Private sync is unavailable while deletion is pending.
            if (!pendingDeletion) ...<Widget>[
              const SizedBox(height: 16),
              _syncCard(context, sync),
            ],
            if (_message != null) ...<Widget>[
              const SizedBox(height: 12),
              IqroStatusBanner(icon: Icons.info_outline, title: _message!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _syncCard(BuildContext context, SyncReport sync) {
    return IqroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.syncNow,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(context.l10n.syncHint),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: sync.status == SyncStatus.syncing ? null : _sync,
              icon: sync.status == SyncStatus.syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(context.l10n.syncNow),
            ),
          ),
          if (sync.status != SyncStatus.idle &&
              sync.status != SyncStatus.syncing) ...<Widget>[
            const SizedBox(height: 10),
            IqroStatusBanner(
              icon: sync.status == SyncStatus.conflict
                  ? Icons.compare_arrows
                  : Icons.cloud_off_outlined,
              title: sync.status == SyncStatus.conflict
                  ? context.l10n.syncConflict
                  : context.l10n.networkError,
            ),
          ],
        ],
      ),
    );
  }

  Widget _signInCard(BuildContext context) {
    return IqroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.signIn,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(context.l10n.guestSyncHint),
          const SizedBox(height: 16),
          if (_challenge == null) ...<Widget>[
            TextField(
              controller: _emailController,
              enabled: !_working,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.email],
              decoration: InputDecoration(
                labelText: context.l10n.email,
                prefixIcon: const Icon(Icons.email_outlined),
                errorText: _emailError,
              ),
              onChanged: (_) {
                if (_emailError != null && _isScreenCurrent()) {
                  setState(() => _emailError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _working ? null : _sendCode,
                child: _working
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text(context.l10n.sendCode),
              ),
            ),
          ] else ...<Widget>[
            TextField(
              controller: _codeController,
              enabled: !_working,
              keyboardType: TextInputType.number,
              autofillHints: const <String>[AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: InputDecoration(
                labelText: context.l10n.verificationCode,
                prefixIcon: const Icon(Icons.password),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _working
                      ? null
                      : () {
                          if (_isScreenCurrent()) {
                            setState(() => _challenge = null);
                          }
                        },
                  child: Text(context.l10n.back),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _working ? null : _verify,
                    child: Text(context.l10n.verify),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _verifiedActions(BuildContext context, AuthSession current) {
    return IqroCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: <Widget>[
          IqroListTile(
            icon: Icons.mark_email_unread_outlined,
            title: context.l10n.feedbackTitle,
            subtitle: context.l10n.feedbackAccountHint,
            onTap: () => context.push('/feedback'),
          ),
          const Divider(height: 1),
          IqroListTile(
            icon: Icons.devices_outlined,
            title: context.l10n.devices,
            subtitle: context.l10n.syncHint,
            onTap: () => context.push('/devices'),
          ),
          const Divider(height: 1),
          IqroListTile(
            icon: Icons.logout,
            title: context.l10n.signOut,
            onTap: _confirmSignOut,
          ),
          const Divider(height: 1),
          IqroListTile(
            icon: Icons.phonelink_erase_outlined,
            title: context.l10n.accountSignOutEverywhere,
            onTap: _confirmSignOutEverywhere,
          ),
        ],
      ),
    );
  }

  Widget _deletionCard(BuildContext context, AuthSession current) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return IqroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.accountDangerZone,
            style: theme.textTheme.labelMedium?.copyWith(color: error),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.accountDeletionTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(context.l10n.accountDeletionDescription),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: error,
                side: BorderSide(color: error),
              ),
              onPressed: _working
                  ? null
                  : () => _runLifecycleAction(
                      _LifecycleAction.request,
                      current.email!,
                    ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(context.l10n.accountDelete),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingDeletionCard(BuildContext context, AuthSession current) {
    final theme = Theme.of(context);
    final scheduled = current.deletionScheduledFor;
    final email = current.email;
    return IqroCard(
      color: theme.colorScheme.errorContainer,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.event_busy_outlined,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.accountPendingDeletionTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.accountPendingDeletionDescription(
              scheduled == null ? '—' : _formatDate(context, scheduled),
            ),
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _working || email == null
                  ? null
                  : () => _runLifecycleAction(_LifecycleAction.cancel, email),
              icon: const Icon(Icons.restore),
              label: Text(context.l10n.accountCancelDeletion),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              // The default primary text is unreadable on the error card.
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
                side: BorderSide(color: theme.colorScheme.onErrorContainer),
              ),
              onPressed: _working ? null : _confirmSignOut,
              icon: const Icon(Icons.logout),
              label: Text(context.l10n.signOut),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(BuildContext context, DateTime value) {
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.yMMMMd(locale).add_Hm().format(value.toLocal());
  }

  Future<void> _sendCode() async {
    if (_working || !_isScreenCurrent()) {
      return;
    }
    final email = _emailController.text.trim().toLowerCase();
    if (!_isValidEmail(email)) {
      setState(() {
        _emailError = context.l10n.invalidEmail;
        _message = null;
      });
      return;
    }
    if (_emailController.text != email) {
      _emailController.value = TextEditingValue(
        text: email,
        selection: TextSelection.collapsed(offset: email.length),
      );
    }
    final request = ++_requestGeneration;
    setState(() {
      _working = true;
      _emailError = null;
      _message = null;
    });
    try {
      final challenge = await widget.controller.startEmail(email);
      if (mounted && _isScreenCurrent(request)) {
        setState(() => _challenge = challenge);
      }
    } on AccountScopeChanged {
      // The account screen is replaced by its scope key on session changes.
    } on ApiException catch (error) {
      if (mounted && _isScreenCurrent(request)) {
        setState(() {
          if (error.statusCode == 400) {
            _emailError = context.l10n.invalidEmail;
          } else {
            _message = error.isOffline
                ? context.l10n.networkError
                : apiErrorText(
                    context.l10n,
                    error,
                    fallback: context.l10n.accountCodeSendError,
                  );
          }
        });
      }
    } finally {
      if (mounted && _isScreenCurrent(request)) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _verify() async {
    final challenge = _challenge;
    if (_working ||
        !_isScreenCurrent() ||
        challenge == null ||
        _codeController.text.length != 6) {
      return;
    }
    final request = ++_requestGeneration;
    final code = _codeController.text;
    setState(() {
      _working = true;
      _message = null;
    });
    // Read before the await: a new account replaces this screen.
    final analytics = ref.read(analyticsProvider.notifier);
    try {
      await widget.controller.verify(challenge, code);
      analytics.track(AnalyticsEvent.login, const {'method': 'email'});
      if (!mounted || !_isScreenCurrent(request)) return;
      final error = ref.read(sessionProvider).error;
      if (error is ApiException) throw error;
    } on AccountScopeChanged {
      // The account screen is replaced by its scope key on session changes.
    } on ApiException catch (error) {
      if (mounted && _isScreenCurrent(request)) {
        setState(
          () => _message = error.isOffline
              ? context.l10n.networkError
              : apiErrorText(
                  context.l10n,
                  error,
                  fallback: context.l10n.accountCodeVerifyError,
                ),
        );
      }
    } finally {
      if (mounted && _isScreenCurrent(request)) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _sync() async {
    if (!_isAccountCurrent()) return;
    final request = ++_requestGeneration;
    final controller = ref.read(syncProvider.notifier);
    late final SyncReport report;
    try {
      report = await controller.run();
    } on AccountScopeChanged {
      return;
    } on Object catch (error) {
      if (mounted &&
          _isAccountCurrent(request) &&
          identical(controller, ref.read(syncProvider.notifier))) {
        setState(
          () => _message = error is ApiException && error.isOffline
              ? context.l10n.networkError
              : apiErrorText(
                  context.l10n,
                  error,
                  fallback: context.l10n.apiErrorUnknown,
                ),
        );
      }
      return;
    }
    if (!mounted ||
        !_isAccountCurrent(request) ||
        !identical(controller, ref.read(syncProvider.notifier))) {
      return;
    }
    if (report.status == SyncStatus.idle) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10n.done}: ${report.pushed + report.pulled}',
          ),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    if (_working || !_isAccountCurrent()) return;
    ++_requestGeneration;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.controller.signOut();
    } on Object {
      // SessionController deactivates the old scope before surfacing a durable
      // logout failure. The replacement screen owns any subsequent action.
    }
  }

  Future<void> _confirmSignOut() async {
    if (_working || !_isAccountCurrent()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.signOut),
        content: Text(context.l10n.signOutConfirmation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && _isAccountCurrent()) {
      await _signOut();
    }
  }

  Future<void> _runLifecycleAction(
    _LifecycleAction action,
    String email,
  ) async {
    if (_working || !_isAccountCurrent()) return;
    final messenger = ScaffoldMessenger.of(context);
    final notice = action == _LifecycleAction.request
        ? context.l10n.accountDeletionScheduledNotice
        : context.l10n.accountDeletionCancelledNotice;
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountLifecycleDialog(
        action: action,
        email: email,
        controller: widget.controller,
      ),
    );
    // The body is rebuilt for the new account status, so the notice goes to
    // the messenger captured before the dialog opened.
    if (completed == true) {
      messenger.showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> _confirmSignOutEverywhere() async {
    if (_working || !_isAccountCurrent()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.accountSignOutEverywhereTitle),
        content: Text(context.l10n.accountSignOutEverywhereDescription),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.accountSignOutEverywhereConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_isAccountCurrent()) return;
    final request = ++_requestGeneration;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.controller.signOutEverywhere();
    } on ApiException catch (error) {
      // The server did not confirm the revocation: this device stays signed in.
      if (mounted && _isAccountCurrent(request)) {
        setState(
          () => _message = error.isOffline
              ? context.l10n.networkError
              : context.l10n.accountSignOutEverywhereError,
        );
      }
    } on Object {
      // As with signOut, a local logout failure is owned by the replacement
      // screen once SessionController has deactivated the account.
    } finally {
      if (mounted && _isScreenCurrent(request)) {
        setState(() => _working = false);
      }
    }
  }

  bool _isScreenCurrent([int? request]) {
    if (!mounted) return false;
    if (request != null && request != _requestGeneration) return false;
    return identical(widget.controller, ref.read(sessionProvider.notifier));
  }

  bool _isAccountCurrent([int? request]) {
    if (!_isScreenCurrent(request)) return false;
    final scope = widget.accountScope;
    return scope != null && widget.database.accountScope.isCurrent(scope);
  }

  bool _isValidEmail(String email) {
    return email.length <= 254 && _emailPattern.hasMatch(email);
  }
}

enum _LifecycleAction { request, cancel }

/// Email re-verification followed by a deletion request or cancellation,
/// mirroring the website: send code -> enter code -> confirm.
class _AccountLifecycleDialog extends StatefulWidget {
  const _AccountLifecycleDialog({
    required this.action,
    required this.email,
    required this.controller,
  });

  final _LifecycleAction action;
  final String email;
  final SessionController controller;

  @override
  State<_AccountLifecycleDialog> createState() =>
      _AccountLifecycleDialogState();
}

class _AccountLifecycleDialogState extends State<_AccountLifecycleDialog> {
  final _codeController = TextEditingController();
  EmailChallenge? _challenge;
  // A consumed challenge cannot be verified twice, so after a successful
  // verification only the lifecycle call itself is retried.
  var _reauthenticated = false;
  var _working = false;
  String? _error;

  bool get _isRequest => widget.action == _LifecycleAction.request;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final challenge = _challenge;
    final canConfirm =
        challenge != null &&
        (_reauthenticated || _codeController.text.length == 6);
    return AlertDialog(
      icon: Icon(
        _isRequest ? Icons.delete_forever_outlined : Icons.restore,
        color: _isRequest ? scheme.error : scheme.primary,
      ),
      title: Text(
        _isRequest
            ? l10n.accountDeletionRequestTitle
            : l10n.accountDeletionCancelTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _isRequest
                  ? l10n.accountDeletionRequestDescription
                  : l10n.accountDeletionCancelDescription,
            ),
            if (challenge != null) ...<Widget>[
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                enabled: !_working && !_reauthenticated,
                keyboardType: TextInputType.number,
                autofillHints: const <String>[AutofillHints.oneTimeCode],
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: l10n.verificationCode,
                  prefixIcon: const Icon(Icons.password),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.back),
        ),
        if (challenge != null && !_reauthenticated)
          TextButton(
            onPressed: _working ? null : _sendCode,
            child: Text(l10n.accountNewCode),
          ),
        FilledButton(
          style: _isRequest
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: _working
              ? null
              : challenge == null
              ? _sendCode
              : canConfirm
              ? _confirm
              : null,
          child: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  challenge == null
                      ? l10n.accountSendCodeTo(widget.email)
                      : _isRequest
                      ? l10n.accountConfirmDeletion
                      : l10n.accountRestore,
                ),
        ),
      ],
    );
  }

  Future<void> _sendCode() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final challenge = await widget.controller.startEmail(widget.email);
      if (!mounted) return;
      _codeController.clear();
      setState(() {
        _challenge = challenge;
        _reauthenticated = false;
      });
    } on AccountScopeChanged {
      _close();
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.isOffline
              ? context.l10n.networkError
              : context.l10n.accountCodeSendError,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirm() async {
    final challenge = _challenge;
    if (_working || challenge == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (!_reauthenticated) {
        try {
          await widget.controller.reauthenticate(
            challenge,
            _codeController.text,
          );
        } on ApiException catch (error) {
          if (mounted) {
            setState(
              () => _error = error.isOffline
                  ? context.l10n.networkError
                  : context.l10n.accountCodeVerifyError,
            );
          }
          return;
        }
        _reauthenticated = true;
      }
      if (_isRequest) {
        await widget.controller.requestAccountDeletion(challenge.id);
      } else {
        await widget.controller.cancelAccountDeletion(challenge.id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AccountScopeChanged {
      _close();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'account_reauthentication_required') {
          // The verification is too old for the server; start over.
          _challenge = null;
          _reauthenticated = false;
          _codeController.clear();
          _error = context.l10n.accountCodeExpired;
        } else {
          _error = error.isOffline
              ? context.l10n.networkError
              : context.l10n.accountActionError;
        }
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _close() {
    if (mounted) Navigator.of(context).pop(false);
  }
}
