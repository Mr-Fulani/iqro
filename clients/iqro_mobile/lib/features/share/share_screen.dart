import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'share_repository.dart';

class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  ShareExperience? _experience;
  ReferralSummary? _summary;
  var _loading = true;
  ({String? ownerId, String locale, bool verified})? _loadKey;
  var _loadGeneration = 0;

  void _synchronizeLoadKey({
    required String? ownerId,
    required String locale,
    required bool verified,
  }) {
    final nextKey = (ownerId: ownerId, locale: locale, verified: verified);
    if (_loadKey == nextKey) return;

    // Account-owned referral URLs and metrics must disappear in the same
    // build that observes an owner/locale change. Waiting for the replacement
    // request would briefly expose the previous account's data.
    _loadKey = nextKey;
    _loadGeneration += 1;
    _experience = null;
    _summary = null;
    _loading = true;

    final generation = _loadGeneration;
    final fallbackTitle = context.l10n.shareTitle;
    final fallbackMessage = context.l10n.shareBody;
    final fallbackCta = context.l10n.shareButton;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadKey != nextKey || generation != _loadGeneration) {
        return;
      }
      _load(
        key: nextKey,
        generation: generation,
        fallbackTitle: fallbackTitle,
        fallbackMessage: fallbackMessage,
        fallbackCta: fallbackCta,
      );
    });
  }

  Future<void> _load({
    required ({String? ownerId, String locale, bool verified}) key,
    required int generation,
    required String fallbackTitle,
    required String fallbackMessage,
    required String fallbackCta,
  }) async {
    final database = ref.read(localDatabaseProvider);
    final accountScope = database.accountScope.current;
    if (accountScope == null ||
        accountScope.userId != key.ownerId ||
        !_sessionMatches(key)) {
      return;
    }
    final repository = ref.read(shareRepositoryProvider);
    try {
      final experience = await repository.experience(
        locale: key.locale,
        fallbackTitle: fallbackTitle,
        fallbackMessage: fallbackMessage,
        fallbackCta: fallbackCta,
        accountScope: accountScope,
      );
      if (!mounted ||
          _loadKey != key ||
          generation != _loadGeneration ||
          !_sessionMatches(key) ||
          !database.accountScope.isCurrent(accountScope)) {
        return;
      }
      final summary = await repository.summary(
        experience.campaignKey,
        accountScope: accountScope,
      );
      if (!mounted ||
          _loadKey != key ||
          generation != _loadGeneration ||
          !_sessionMatches(key) ||
          !database.accountScope.isCurrent(accountScope)) {
        return;
      }
      setState(() {
        _experience = experience;
        _summary = summary;
        _loading = false;
      });
    } on AccountScopeChanged {
      // A handoff cancels this load; the new account key schedules its own.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final ownerId = session.valueOrNull?.userId;
    final verified = session.valueOrNull?.isVerified == true;
    final locale = Localizations.localeOf(context).languageCode;
    _synchronizeLoadKey(ownerId: ownerId, locale: locale, verified: verified);
    final experience = _experience;
    final loadKey = _loadKey!;
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.shareApp),
      body: KeyedSubtree(
        key: ValueKey(
          '${loadKey.ownerId ?? '<none>'}:${loadKey.locale}:'
          '${loadKey.verified}',
        ),
        child: _loading || experience == null
            ? const IqroLoading()
            : IqroPage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    IqroCard(
                      color: context.iqroColors.ink,
                      borderColor: Colors.transparent,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: <Widget>[
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.ios_share,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            experience.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            experience.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .72),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: Builder(
                              builder: (buttonContext) => FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: context.iqroColors.ink,
                                ),
                                onPressed: () async {
                                  final database = ref.read(
                                    localDatabaseProvider,
                                  );
                                  final accountScope =
                                      database.accountScope.current;
                                  final actionKey = _loadKey;
                                  final actionGeneration = _loadGeneration;
                                  if (accountScope == null ||
                                      actionKey == null ||
                                      actionKey.ownerId !=
                                          accountScope.userId ||
                                      actionKey.verified != verified ||
                                      actionGeneration != _loadGeneration ||
                                      !database.accountScope.isCurrent(
                                        accountScope,
                                      )) {
                                    return;
                                  }
                                  final box = buttonContext.findRenderObject();
                                  final origin = box is RenderBox
                                      ? box.localToGlobal(Offset.zero) &
                                            box.size
                                      : null;
                                  await ref
                                      .read(shareRepositoryProvider)
                                      .openShareSheet(
                                        experience,
                                        sourceScreen: 'settings',
                                        sharePositionOrigin: origin,
                                        accountScope: accountScope,
                                      );
                                },
                                icon: const Icon(Icons.ios_share),
                                label: Text(experience.ctaLabel),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    IqroCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            experience.url,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final database = ref.read(
                                  localDatabaseProvider,
                                );
                                final accountScope =
                                    database.accountScope.current;
                                final actionKey = _loadKey;
                                final actionGeneration = _loadGeneration;
                                if (accountScope == null ||
                                    actionKey == null ||
                                    actionKey.ownerId != accountScope.userId ||
                                    actionKey.verified != verified ||
                                    actionGeneration != _loadGeneration ||
                                    !database.accountScope.isCurrent(
                                      accountScope,
                                    )) {
                                  return;
                                }
                                final copiedMessage = context.l10n.linkCopied;
                                await Clipboard.setData(
                                  ClipboardData(text: experience.url),
                                );
                                if (!mounted ||
                                    actionKey != _loadKey ||
                                    actionGeneration != _loadGeneration ||
                                    !_sessionMatches(actionKey) ||
                                    !database.accountScope.isCurrent(
                                      accountScope,
                                    )) {
                                  return;
                                }
                                await ref
                                    .read(shareRepositoryProvider)
                                    .trackCopy(
                                      experience,
                                      sourceScreen: 'settings',
                                      accountScope: accountScope,
                                    );
                                if (!context.mounted ||
                                    actionKey != _loadKey ||
                                    actionGeneration != _loadGeneration ||
                                    !_sessionMatches(actionKey) ||
                                    !database.accountScope.isCurrent(
                                      accountScope,
                                    )) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(copiedMessage)),
                                );
                              },
                              icon: const Icon(Icons.copy),
                              label: Text(context.l10n.copyLink),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    IqroStatusBanner(
                      icon: experience.remote
                          ? Icons.cloud_done_outlined
                          : Icons.offline_bolt_outlined,
                      title: experience.remote
                          ? context.l10n.remoteCopy
                          : context.l10n.bundledCopy,
                    ),
                    const SizedBox(height: 18),
                    if (_summary != null)
                      IqroCard(
                        color: context.iqroColors.sand,
                        borderColor: Colors.transparent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.l10n.referralSummary,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _Metric(
                                    label: context.l10n.invited,
                                    value: _summary!.invited,
                                  ),
                                ),
                                Expanded(
                                  child: _Metric(
                                    label: context.l10n.qualified,
                                    value: _summary!.qualified,
                                  ),
                                ),
                                Expanded(
                                  child: _Metric(
                                    label: context.l10n.rewardBalance,
                                    value: _summary!.rewardBalance,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else if (!verified)
                      IqroStatusBanner(
                        icon: Icons.lock_outline,
                        title: context.l10n.referralRequiresAccount,
                        color: context.iqroColors.lavender,
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  bool _sessionMatches(({String? ownerId, String locale, bool verified}) key) {
    final session = ref.read(sessionProvider).valueOrNull;
    return session?.userId == key.ownerId &&
        (session?.isVerified == true) == key.verified;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('$value', style: Theme.of(context).textTheme.headlineMedium),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
