/// Speeds the reader's speed button steps through, in order.
const playbackSpeeds = <double>[1, 1.25, 1.5, 0.75];

/// The speed after [speed]; an unknown speed starts the cycle over.
double nextPlaybackSpeed(double speed) {
  final index = playbackSpeeds.indexOf(speed);
  return playbackSpeeds[(index + 1) % playbackSpeeds.length];
}

/// «1», «1.25»: whole speeds without a decimal point.
String playbackSpeedLabel(double speed) =>
    speed == speed.roundToDouble() ? '${speed.toInt()}' : '$speed';
