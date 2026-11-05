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

/// The Audio player's speeds, in the order the Mushaf player's button steps
/// through them; the site steps the same way.
const playerSpeeds = <double>[1, 1.25, 1.5, 2, 0.75];

/// The player speed after [speed]; an unknown speed starts the cycle over.
double nextPlayerSpeed(double speed) {
  final index = playerSpeeds.indexOf(speed);
  return playerSpeeds[(index + 1) % playerSpeeds.length];
}
