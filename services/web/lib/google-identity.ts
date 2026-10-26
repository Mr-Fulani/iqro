// Google Identity Services ("Sign in with Google" button and One Tap).
// The script is loaded on demand, only where the button is shown, and only
// when the backend reports a configured client ID.

const GSI_SCRIPT_URL = "https://accounts.google.com/gsi/client";

type CredentialResponse = { credential: string };

type GoogleAccountsId = {
  initialize: (options: {
    client_id: string;
    callback: (response: CredentialResponse) => void;
    auto_select?: boolean;
    cancel_on_tap_outside?: boolean;
    context?: "signin" | "signup" | "use";
    itp_support?: boolean;
    use_fedcm_for_prompt?: boolean;
    use_fedcm_for_button?: boolean;
  }) => void;
  renderButton: (parent: HTMLElement, options: Record<string, string | number>) => void;
  prompt: () => void;
  cancel: () => void;
  disableAutoSelect: () => void;
};

type GoogleWindow = Window & { google?: { accounts?: { id?: GoogleAccountsId } } };

let scriptPromise: Promise<GoogleAccountsId> | null = null;
let initializedClientId: string | null = null;
let credentialListener: ((idToken: string) => void) | null = null;

function accountsId(): GoogleAccountsId | null {
  if (typeof window === "undefined") return null;
  return (window as GoogleWindow).google?.accounts?.id ?? null;
}

export function loadGoogleIdentity(): Promise<GoogleAccountsId> {
  const ready = accountsId();
  if (ready) return Promise.resolve(ready);
  if (!scriptPromise) {
    scriptPromise = new Promise<GoogleAccountsId>((resolve, reject) => {
      const script = document.createElement("script");
      script.src = GSI_SCRIPT_URL;
      script.async = true;
      script.onload = () => {
        const loaded = accountsId();
        if (loaded) resolve(loaded);
        else reject(new Error("Google Identity Services did not initialize"));
      };
      script.onerror = () => reject(new Error("Google Identity Services failed to load"));
      document.head.appendChild(script);
    }).catch((error: unknown) => {
      // A blocked or offline load may succeed on the next visit to the page.
      scriptPromise = null;
      throw error;
    });
  }
  return scriptPromise;
}

/**
 * Initializes GIS once per client ID. The callback always goes to the most
 * recently mounted button, so a re-render never signs in through a stale one.
 */
export function prepareGoogleIdentity(
  google: GoogleAccountsId,
  clientId: string,
  onCredential: (idToken: string) => void,
): void {
  credentialListener = onCredential;
  if (initializedClientId === clientId) return;
  google.initialize({
    client_id: clientId,
    callback: (response) => credentialListener?.(response.credential),
    auto_select: false,
    cancel_on_tap_outside: true,
    context: "signin",
    itp_support: true,
    use_fedcm_for_prompt: true,
    use_fedcm_for_button: true,
  });
  initializedClientId = clientId;
}

/** After sign-out Google asks which account to use instead of reusing the last one. */
export function disableGoogleAutoSelect(): void {
  accountsId()?.disableAutoSelect();
}
