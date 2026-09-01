import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_experience == null && _loading) _load();
  }

  Future<void> _load() async {
    final locale = Localizations.localeOf(context).languageCode;
    final repository = ref.read(shareRepositoryProvider);
    final experience = await repository.experience(
      locale: locale,
      fallbackTitle: context.l10n.shareTitle,
      fallbackMessage: context.l10n.shareBody,
      fallbackCta: context.l10n.shareButton,
    );
    final summary = await repository.summary(experience.campaignKey);
    if (mounted) {
      setState(() {
        _experience = experience;
        _summary = summary;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final experience = _experience;
    final verified = ref.watch(sessionProvider).valueOrNull?.isVerified == true;
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.shareApp),
      body: _loading || experience == null
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
                                final box = buttonContext.findRenderObject();
                                final origin = box is RenderBox
                                    ? box.localToGlobal(Offset.zero) & box.size
                                    : null;
                                await ref
                                    .read(shareRepositoryProvider)
                                    .openShareSheet(
                                      experience,
                                      sourceScreen: 'settings',
                                      sharePositionOrigin: origin,
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
                              final copiedMessage = context.l10n.linkCopied;
                              await Clipboard.setData(
                                ClipboardData(text: experience.url),
                              );
                              await ref
                                  .read(shareRepositoryProvider)
                                  .trackCopy(
                                    experience,
                                    sourceScreen: 'settings',
                                  );
                              if (!context.mounted) return;
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
    );
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
