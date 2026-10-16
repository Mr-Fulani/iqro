import { useSyncExternalStore } from "react";

const subscribeToNothing = () => () => {};

/** False in server HTML and during hydration, true once the client has taken over. */
export function useHydrated(): boolean {
  return useSyncExternalStore(subscribeToNothing, () => true, () => false);
}
