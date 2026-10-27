import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_error_text.dart';
import '../../core/network/api_exception.dart';

/// "Continue with Google": Android's account sheet, then one tap on the
/// account. Shows nothing until Google sign-in is configured on the server,
/// so the email code stays the only way in until then.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({
    this.trySilentSignIn = false,
    this.showEmailDivider = false,
    this.showSignedInAs = false,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Signs in without asking when this app already used a Google account
  /// (for example after reinstalling). Tried at most once per app run.
  final bool trySilentSignIn;

  /// Adds "or with an email code" below, for screens with the email form.
  final bool showEmailDivider;

  /// Once signed in, shows the account instead of the button.
  final bool showSignedInAs;

  /// Applied only while something is shown.
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  var _working = false;
  var _silentStarted = false;
  String? _error;

  Future<void> _signInSilently() async {
    final idToken = await ref
        .read(googleSignInGatewayProvider)
        .signInSilently();
    if (idToken == null || !mounted || _working) return;
    await _complete(idToken);
  }

  Future<void> _chooseAccount() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    String? idToken;
    try {
      idToken = await ref.read(googleSignInGatewayProvider).chooseAccount();
    } on Object {
      if (mounted) setState(() => _error = context.l10n.apiErrorGoogleFailed);
    }
    if (idToken == null) {
      if (mounted) setState(() => _working = false);
      return;
    }
    await _complete(idToken);
  }

  Future<void> _complete(String idToken) async {
    if (mounted) {
      setState(() {
        _working = true;
        _error = null;
      });
    }
    // Read before the await: a new account rebuilds the screen around us.
    final analytics = ref.read(analyticsProvider.notifier);
    final controller = ref.read(sessionProvider.notifier);
    try {
      await controller.signInWithGoogle(idToken);
      analytics.track(AnalyticsEvent.login, const {'method': 'google'});
    } on AccountScopeChanged {
      // The session changed meanwhile; the new screen owns what follows.
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException && error.isOffline
              ? context.l10n.networkError
              : apiErrorText(
                  context.l10n,
                  error,
                  fallback: context.l10n.apiErrorGoogleFailed,
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing else is read until Google sign-in is known to be available.
    final available = ref.watch(googleSignInAvailableProvider).valueOrNull;
    if (available != true) return const SizedBox.shrink();
    final session = ref.watch(sessionProvider).valueOrNull;
    final email = session?.email;
    if (session?.isVerified == true && email != null) {
      if (!widget.showSignedInAs) return const SizedBox.shrink();
      return Padding(
        padding: widget.padding,
        child: IqroStatusBanner(
          icon: Icons.verified_user_outlined,
          title: context.l10n.googleSignedInAs(email),
        ),
      );
    }
    if (widget.trySilentSignIn && !_silentStarted) {
      _silentStarted = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_signInSilently()),
      );
    }
    final theme = Theme.of(context);
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('google-sign-in'),
            onPressed: _working ? null : _chooseAccount,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            icon: _working
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const SizedBox.square(
                    dimension: 20,
                    child: CustomPaint(painter: _GoogleLogoPainter()),
                  ),
            label: Text(context.l10n.googleContinue),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            IqroStatusBanner(icon: Icons.error_outline, title: _error!),
          ],
          if (widget.showEmailDivider) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    context.l10n.googleOrEmail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// Google's four-colour "G" mark, drawn so the app ships no extra asset.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final stroke = side * 0.2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (side - stroke) / 2,
    );
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const degree = math.pi / 180;
    // Angles run clockwise from three o'clock; the gap is on the right.
    canvas
      ..drawArc(rect, -45 * degree, -90 * degree, false, arc(_red))
      ..drawArc(rect, -135 * degree, -90 * degree, false, arc(_yellow))
      ..drawArc(rect, 135 * degree, -90 * degree, false, arc(_green))
      ..drawArc(rect, 45 * degree, -45 * degree, false, arc(_blue));
    final center = rect.center;
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - stroke / 2,
        rect.right + stroke / 2,
        center.dy + stroke / 2,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
