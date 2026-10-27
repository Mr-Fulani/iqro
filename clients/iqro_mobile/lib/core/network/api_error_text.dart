import '../../l10n/generated/app_localizations.dart';
import 'api_exception.dart';

/// User-facing text for a backend error, chosen by its stable `code` like the
/// site's `API_ERROR_MESSAGES`. The server `detail` is not localized for the
/// app, so it is never shown; unknown codes and other errors use [fallback].
String apiErrorText(
  AppLocalizations l10n,
  Object error, {
  required String fallback,
}) {
  if (error is! ApiException) return fallback;
  return switch (error.code) {
    'email_challenge_invalid' => l10n.apiErrorEmailInvalid,
    'email_challenge_expired' => l10n.apiErrorEmailExpired,
    'email_delivery_failed' => l10n.apiErrorEmailDelivery,
    'google_token_invalid' => l10n.apiErrorGoogleFailed,
    'google_email_unverified' => l10n.apiErrorGoogleEmailUnverified,
    'google_sign_in_disabled' ||
    'google_sign_in_unavailable' => l10n.apiErrorGoogleUnavailable,
    'auth_rate_limited' || 'reading_rate_limited' => l10n.apiErrorRateLimited,
    'installation_identity_missing' => l10n.apiErrorInstallationMissing,
    'account_link_unavailable' => l10n.apiErrorLinkUnavailable,
    'identity_already_linked' => l10n.apiErrorIdentityLinked,
    'account_reauthentication_required' => l10n.apiErrorReauthRequired,
    'account_lifecycle_unavailable' => l10n.apiErrorLifecycleUnavailable,
    'current_device_revoke_conflict' => l10n.apiErrorCurrentDevice,
    'device_not_found' => l10n.apiErrorDeviceNotFound,
    'sync_cursor_expired' => l10n.apiErrorCursorExpired,
    _ => fallback,
  };
}
