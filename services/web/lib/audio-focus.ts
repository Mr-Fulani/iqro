export type AudioPauseReason = "focus" | "navigation";

type AudioPauseHandler = (reason: AudioPauseReason) => void;

const audioPlayers = new Map<symbol, AudioPauseHandler>();

export function registerAudioPlayer(
  id: symbol,
  pause: AudioPauseHandler,
): () => void {
  const registration = pause;
  audioPlayers.set(id, registration);
  return () => {
    if (audioPlayers.get(id) === registration) audioPlayers.delete(id);
  };
}

export function claimAudioFocus(id: symbol): void {
  for (const [otherId, pause] of audioPlayers) {
    if (otherId !== id) pause("focus");
  }
}

export function pauseAllAudioPlayers(
  reason: AudioPauseReason = "navigation",
): void {
  for (const pause of audioPlayers.values()) pause(reason);
}
