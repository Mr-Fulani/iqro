import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/offline_storage_quota.dart';
import '../../core/theme/iqro_theme.dart';
import 'offline_storage_repository.dart';

class OfflineStorageScreen extends ConsumerStatefulWidget {
  const OfflineStorageScreen({super.key});

  @override
  ConsumerState<OfflineStorageScreen> createState() =>
      _OfflineStorageScreenState();
}

class _OfflineStorageScreenState extends ConsumerState<OfflineStorageScreen> {
  String? _deletingPackageId;

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(offlinePackagesProvider);
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.offlineStorage,
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: _deletingPackageId == null
                ? () => ref.invalidate(offlinePackagesProvider)
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: packages.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => IqroPage(
          child: IqroStatusBanner(
            icon: Icons.error_outline,
            title: context.l10n.storageReadFailed,
            message: context.l10n.tryAgain,
            actionLabel: context.l10n.retry,
            onAction: () => ref.invalidate(offlinePackagesProvider),
          ),
        ),
        data: (items) => _content(items),
      ),
    );
  }

  Widget _content(List<OfflinePackageSummary> packages) {
    final totalUsed = packages.fold<int>(
      0,
      (sum, package) => sum + package.usedBytes,
    );
    return IqroPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroStatusBanner(
            icon: Icons.offline_pin_outlined,
            title: context.l10n.offlineStorageUsed(_formatBytes(totalUsed)),
            message:
                '${context.l10n.offlineStorageDescription}\n'
                '${context.l10n.offlineStorageQuota(_formatBytes(offlineStorageQuotaBytes))}',
            color: context.iqroColors.sand,
          ),
          const SizedBox(height: 22),
          IqroSectionHeader(title: context.l10n.downloadedContent),
          const SizedBox(height: 10),
          if (packages.isEmpty)
            IqroCard(
              child: Row(
                children: <Widget>[
                  const Icon(Icons.cloud_download_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.l10n.noOfflinePackages)),
                ],
              ),
            )
          else
            for (
              var index = 0;
              index < packages.length;
              index += 1
            ) ...<Widget>[
              _OfflinePackageCard(
                package: packages[index],
                deleting: _deletingPackageId == packages[index].packageId,
                onDelete: packages[index].isDownloading
                    ? null
                    : () => _confirmDelete(packages[index]),
              ),
              if (index < packages.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(OfflinePackageSummary package) async {
    if (_deletingPackageId != null) return;
    final player = ref.read(audioControllerProvider);
    final isPlayingFromPackage =
        package.isAudio &&
        player.track?.url.startsWith('file:') == true &&
        package.contentKey == 'recitation:${player.track?.recitationId}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteOfflinePackage),
        content: Text(
          isPlayingFromPackage
              ? context.l10n.deletePlayingAudioConfirmation(
                  _packageTitle(context, package),
                  _formatBytes(package.usedBytes),
                )
              : context.l10n.deleteOfflinePackageConfirmation(
                  _packageTitle(context, package),
                  _formatBytes(package.usedBytes),
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingPackageId = package.packageId);
    try {
      if (isPlayingFromPackage) {
        await ref.read(audioControllerProvider.notifier).stop();
      }
      await ref
          .read(offlineStorageRepositoryProvider)
          .deletePackage(package.packageId);
      ref.read(audioRepositoryProvider).clearPlaybackCache();
      ref.invalidate(mushafDownloadProvider);
      ref.invalidate(audioDownloadProvider);
      ref.invalidate(mushafPageProvider);
      ref.invalidate(offlinePackagesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.offlinePackageDeleted)),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.offlinePackageDeleteFailed)),
      );
    } finally {
      if (mounted) setState(() => _deletingPackageId = null);
    }
  }
}

class _OfflinePackageCard extends StatelessWidget {
  const _OfflinePackageCard({
    required this.package,
    required this.deleting,
    required this.onDelete,
  });

  final OfflinePackageSummary package;
  final bool deleting;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = package.totalItems <= 0
        ? null
        : '${package.completedItems} / ${package.totalItems}';
    final declared = package.totalBytes <= 0
        ? null
        : context.l10n.packageTotalSize(_formatBytes(package.totalBytes));
    return IqroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: package.isMushaf
                      ? context.iqroColors.sand
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  package.isMushaf
                      ? Icons.menu_book_outlined
                      : Icons.headphones_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _packageTitle(context, package),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _packageSubtitle(context, package),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (deleting)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: package.isDownloading
                      ? context.l10n.downloadInProgress
                      : context.l10n.deleteOfflinePackage,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Chip(label: Text(_formatBytes(package.usedBytes))),
              if (progress != null) Chip(label: Text(progress)),
              if (declared != null) Chip(label: Text(declared)),
              Chip(label: Text(_statusLabel(context, package.status))),
            ],
          ),
        ],
      ),
    );
  }
}

String _packageTitle(BuildContext context, OfflinePackageSummary package) {
  if (package.isMushaf) return context.l10n.offlineMushaf;
  return package.reciterNameFor(Localizations.localeOf(context).languageCode) ??
      context.l10n.offlineAudio;
}

String _packageSubtitle(BuildContext context, OfflinePackageSummary package) {
  if (package.isMushaf) return context.l10n.completeMushafPages;
  final quality = switch (package.quality) {
    'economy' => context.l10n.qualityEconomy,
    'standard' => context.l10n.qualityStandard,
    'high' => context.l10n.qualityHigh,
    _ => context.l10n.qualityAutomatic,
  };
  return '${context.l10n.completeRecitation} · $quality';
}

String _statusLabel(BuildContext context, String status) => switch (status) {
  'ready' => context.l10n.availableOffline,
  'downloading' => context.l10n.downloadInProgress,
  'failed' => context.l10n.downloadFailed,
  _ => context.l10n.notReady,
};

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    final kilobytes = bytes / 1024;
    return '${kilobytes.toStringAsFixed(kilobytes >= 100 ? 0 : 1)} KB';
  }
  final megabytes = bytes / (1024 * 1024);
  if (megabytes < 1024) {
    return '${megabytes.toStringAsFixed(megabytes >= 100 ? 0 : 1)} MB';
  }
  final gigabytes = megabytes / 1024;
  return '${gigabytes.toStringAsFixed(gigabytes >= 10 ? 1 : 2)} GB';
}
