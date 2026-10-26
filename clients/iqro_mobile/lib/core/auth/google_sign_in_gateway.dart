import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// "Sign in with Google" through Android Credential Manager. Screens talk to
/// this seam, so widget tests run without the platform plugin.
abstract interface class GoogleSignInGateway {
  /// Whether the button is shown: Android with Google sign-in configured on
  /// the server. An offline check is retried on the next call.
  Future<bool> isAvailable();

  /// Opens Google's account sheet. Returns an ID token, or null when the
  /// person closes the sheet.
  Future<String?> chooseAccount();

  /// One tap for an account already used with this app, without asking when
  /// there is none. Tried at most once per app run.
  Future<String?> signInSilently();

  /// Forgets the chosen account, so the next sign-in asks which one to use.
  Future<void> signOut();
}

class PluginGoogleSignInGateway implements GoogleSignInGateway {
  PluginGoogleSignInGateway(this._serverClientId, {GoogleSignIn? plugin})
    : _plugin = plugin ?? GoogleSignIn.instance;

  /// The web OAuth client ID from the backend; null while not configured.
  final Future<String?> Function() _serverClientId;
  final GoogleSignIn _plugin;
  Future<bool>? _ready;
  var _silentAttempted = false;

  static bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isAvailable() async {
    if (!_supportedPlatform) return false;
    final ready = _ready ??= _initialize();
    try {
      return await ready;
    } on Object {
      if (identical(_ready, ready)) _ready = null;
      return false;
    }
  }

  // The plugin may be initialized only once per process.
  Future<bool> _initialize() async {
    final clientId = await _serverClientId();
    if (clientId == null) return false;
    await _plugin.initialize(serverClientId: clientId);
    return true;
  }

  @override
  Future<String?> chooseAccount() async {
    if (!await isAvailable()) return null;
    try {
      final account = await _plugin.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<String?> signInSilently() async {
    if (_silentAttempted || !await isAvailable()) return null;
    _silentAttempted = true;
    try {
      final account = await _plugin.attemptLightweightAuthentication();
      return account?.authentication.idToken;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    if (!await isAvailable()) return;
    try {
      await _plugin.signOut();
    } on Object {
      // Best effort: at worst Google preselects the previous account.
    }
  }
}
