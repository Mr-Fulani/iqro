"use client";

import { api, ApiError } from "../../lib/api";

/**
 * Runs a request that needs an account: a guest account is created on demand,
 * and once more when the server no longer knows the session.
 */
export async function withGuestSession<T>(
  loginGuest: () => Promise<unknown>,
  run: () => Promise<T>,
): Promise<T> {
  if (!api.getSession() && !(await loginGuest())) throw new Error("No session");
  try {
    return await run();
  } catch (error) {
    if (error instanceof ApiError && error.status === 401 && (await loginGuest())) return run();
    throw error;
  }
}
