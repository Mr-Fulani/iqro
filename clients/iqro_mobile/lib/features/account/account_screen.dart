import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/auth/auth_session.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_exception.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/iqro_theme.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  EmailChallenge? _challenge;
  String? _message;
  var _working = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncProvider);
    final current = session.valueOrNull;
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.personalProfile),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IqroCard(
              color: current?.isVerified == true
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
                      current?.isVerified == true
                          ? Icons.person
                          : Icons.shield_outlined,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          current?.email ?? context.l10n.readingAsGuest,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          current?.isVerified == true
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
            if (current?.isVerified != true)
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
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _working ? null : _sendCode,
                child: Text(context.l10n.sendCode),
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
                      : () => setState(() => _challenge = null),
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
          ),
          const Divider(height: 1),
          IqroListTile(
            icon: Icons.logout,
            title: context.l10n.signOut,
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCode() async {
    if (!_emailController.text.contains('@')) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final challenge = await ref
          .read(sessionProvider.notifier)
          .startEmail(_emailController.text);
      if (mounted) setState(() => _challenge = challenge);
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verify() async {
    final challenge = _challenge;
    if (challenge == null || _codeController.text.length != 6) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .verify(challenge, _codeController.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _sync() async {
    final report = await ref.read(syncProvider.notifier).run();
    if (!mounted) return;
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
}
