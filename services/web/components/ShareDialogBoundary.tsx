"use client";

import { Component, Suspense } from "react";
import type { ReactNode } from "react";

/**
 * Keeps the page working when a share dialog's chunk does not load (a network
 * blip, or a deploy that replaced the file): nothing is shown and `onFailure`
 * shares the text instead. React.lazy keeps the rejected import, so
 * `onFailure` also starts a fresh one for the next press.
 */
export class ShareDialogBoundary extends Component<
  { children: ReactNode; onFailure: () => void },
  { failed: boolean }
> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch() {
    this.props.onFailure();
  }

  render() {
    return this.state.failed ? null : <Suspense fallback={null}>{this.props.children}</Suspense>;
  }
}
