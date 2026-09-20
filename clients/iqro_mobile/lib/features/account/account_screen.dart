import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/auth/auth_session.dart';
import '../../core/design_system/iqro_widgets.dart';
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
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.personalProfile),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IqroCard(
              color: verified
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
                      verified ? Icons.person : Icons.shield_outlined,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          verified
                              ? current!.email!
                              : context.l10n.readingAsGuest,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          verified
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
            if (!verified)
              _signInCard(context)
            else
              _verifiedActions(context, current!),
            const SizedBox(height: 16),
            IqroCard(
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
                      onPressed: sync.status == SyncStatus.syncing
                          ? null
                          : _sync,
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
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 12),
              IqroStatusBanner(icon: Icons.info_outline, title: _message!),
            ],
          ],
        ),
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
        ],
      ),
    );
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
                : error.message;
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
    try {
      await widget.controller.verify(challenge, code);
      if (!mounted || !_isScreenCurrent(request)) return;
      final error = ref.read(sessionProvider).error;
      if (error is ApiException) throw error;
    } on AccountScopeChanged {
      // The account screen is replaced by its scope key on session changes.
    } on ApiException catch (error) {
      if (mounted && _isScreenCurrent(request)) {
        setState(() => _message = error.message);
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
        setState(() => _message = error.toString());
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
