import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);
    final locale = Localizations.localeOf(context).languageCode;
    final durationMs = state.duration.inMilliseconds;
    final positionMs = state.position.inMilliseconds.clamp(
      0,
      durationMs == 0 ? 1 : durationMs,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF061D18),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Column(
          children: <Widget>[
            Text(
              context.l10n.nowPlaying,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              context.l10n.quranSubtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .6),
                fontSize: 11,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 28),
          child: Column(
            children: <Widget>[
              _Artwork(
                url: state.reciter?.portraitUrl,
                initials: state.reciter?.initials ?? 'IQ',
              ),
              const SizedBox(height: 28),
              IqroEyebrow(
                '${context.l10n.surah} 1 · ${context.l10n.ayah} 1',
                light: true,
              ),
              const SizedBox(height: 8),
              Text(
                state.active ? state.surahName : context.l10n.noAudio,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                state.reciter?.nameFor(locale) ?? context.l10n.chooseReciter,
                style: TextStyle(color: Colors.white.withValues(alpha: .65)),
              ),
              const SizedBox(height: 26),
              Slider(
                value: positionMs.toDouble(),
                min: 0,
                max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                onChanged: state.active
                    ? (value) =>
                          controller.seek(Duration(milliseconds: value.round()))
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(_duration(state.position), style: _metaStyle),
                    Text(_duration(state.duration), style: _metaStyle),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  IconButton(
                    onPressed: state.active
                        ? () => controller.seek(
                            Duration(
                              milliseconds: (positionMs - 10000).clamp(
                                0,
                                durationMs,
                              ),
                            ),
                          )
                        : null,
                    color: Colors.white,
                    iconSize: 28,
                    icon: const Icon(Icons.replay_10),
                  ),
                  IconButton(
                    onPressed: state.active
                        ? () => controller.seek(
                            Duration(
                              milliseconds: (positionMs - 30000).clamp(
                                0,
                                durationMs,
                              ),
                            ),
                          )
                        : null,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: IconButton.filled(
                      tooltip: state.playing
                          ? context.l10n.pause
                          : context.l10n.play,
                      onPressed: state.active ? controller.toggle : null,
                      iconSize: 38,
                      icon: state.buffering
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : Icon(
                              state.playing ? Icons.pause : Icons.play_arrow,
                            ),
                    ),
                  ),
                  IconButton(
                    onPressed: state.active
                        ? () => controller.seek(
                            Duration(
                              milliseconds: (positionMs + 30000).clamp(
                                0,
                                durationMs,
                              ),
                            ),
                          )
                        : null,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_next),
                  ),
                  IconButton(
                    onPressed: state.active
                        ? () => controller.seek(
                            Duration(
                              milliseconds: (positionMs + 10000).clamp(
                                0,
                                durationMs,
                              ),
                            ),
                          )
                        : null,
                    color: Colors.white,
                    iconSize: 28,
                    icon: const Icon(Icons.forward_10),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.25,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  _PlayerOption(
                    icon: Icons.speed,
                    title: context.l10n.speed,
                    value: '${state.speed}×',
                    onTap: () => _chooseSpeed(context, controller, state.speed),
                  ),
                  _PlayerOption(
                    icon: Icons.timer_outlined,
                    title: context.l10n.sleepTimer,
                    value: state.sleepTimerMinutes == null
                        ? context.l10n.off
                        : '${state.sleepTimerMinutes} ${context.l10n.minutes}',
                    onTap: () => _chooseTimer(context, controller),
                  ),
                  _PlayerOption(
                    icon: Icons.layers_outlined,
                    title: context.l10n.range,
                    value: context.l10n.soon,
                    onTap: null,
                  ),
                  _PlayerOption(
                    icon: Icons.repeat,
                    title: context.l10n.repeat,
                    value: state.repeatEnabled
                        ? context.l10n.repeatOn
                        : context.l10n.repeatOff,
                    onTap: controller.toggleRepeat,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF103E34),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.phone_android, color: Color(0xFF98DBC7)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.backgroundPlayback,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.check, color: Color(0xFF98DBC7)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _metaStyle = TextStyle(color: Color(0x99FFFFFF), fontSize: 11);

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _chooseSpeed(
    BuildContext context,
    dynamic controller,
    double current,
  ) async {
    final speed = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final value in const <double>[.75, 1, 1.25, 1.5, 2])
                ListTile(
                  leading: Icon(
                    value == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text('$value×'),
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (speed != null) await controller.setSpeed(speed);
  }

  Future<void> _chooseTimer(BuildContext context, dynamic controller) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(context.l10n.off),
              onTap: () => Navigator.pop(context, 0),
            ),
            for (final value in const <int>[10, 20, 30, 60])
              ListTile(
                title: Text('$value ${context.l10n.minutes}'),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    controller.setSleepTimer(
      minutes == null || minutes == 0 ? null : Duration(minutes: minutes),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.initials});
  final String? url;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      height: 210,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: <Color>[
            Color(0xFF2E7463),
            Color(0xFF0C392F),
            Color(0xFF061D18),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: CircleAvatar(
        backgroundColor: const Color(0xFF255E51),
        backgroundImage: url == null ? null : CachedNetworkImageProvider(url!),
        child: url == null
            ? Text(
                initials,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: Colors.white),
              )
            : null,
      ),
    );
  }
}

class _PlayerOption extends StatelessWidget {
  const _PlayerOption({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D3029),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, color: const Color(0xFFB6E8D9)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
