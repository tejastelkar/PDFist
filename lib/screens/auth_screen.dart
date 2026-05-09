import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/app_config.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isSignIn = true;
  String _email = '';
  String _pw = '';
  bool _emailFocused = false;
  bool _pwFocused = false;
  bool _loading = false;
  String? _error;

  bool get _canSubmit => _email.isNotEmpty && _pw.length >= 6 && !_loading;

  void _setAuth() {
    ref.read(isAuthenticatedProvider.notifier).state = true;
    ref.read(isAnonymousProvider.notifier).state = false;
    context.go('/home');
  }

  void _setAnon() {
    AuthService.instance.continueAnonymously();
    ref.read(isAuthenticatedProvider.notifier).state = true;
    ref.read(isAnonymousProvider.notifier).state = true;
    context.go('/home');
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!kFirebaseEnabled) {
      // Firebase not set up yet — let the user in anonymously so they can
      // still use all local PDF tools.
      _setAnon();
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignIn) {
        await AuthService.instance.signInWithEmail(_email, _pw);
      } else {
        await AuthService.instance.createAccount(_email, _pw);
      }
      if (mounted) _setAuth();
    } catch (e) {
      if (mounted) setState(() { _error = _friendly(e); _loading = false; });
    }
  }

  Future<void> _googleSignIn() async {
    if (!kFirebaseEnabled) { _setAnon(); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.signInWithGoogle();
      if (mounted) _setAuth();
    } catch (e) {
      if (mounted) setState(() { _error = _friendly(e); _loading = false; });
    }
  }

  String _friendly(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('user-not-found')) return 'No account with that email.';
    if (msg.contains('email-already-in-use')) return 'Email already in use.';
    if (msg.contains('weak-password')) return 'Password must be ≥ 6 characters.';
    if (msg.contains('cancelled') || msg.contains('canceled')) return 'Sign in cancelled.';
    if (msg.contains('not configured')) {
      return 'Firebase not set up. Continuing offline.';
    }
    return 'Something went wrong. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // masthead
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PDFIST  /  ENTRY',
                      style: AppTextStyles.mono(10, color: AppColors.faint)),
                  Text(_isSignIn ? 'I  OF  II' : 'II  OF  II',
                      style: AppTextStyles.mono(10, color: AppColors.faint)),
                ],
              ),
            ),
            // hero
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: -18,
                    top: -20,
                    child: Text(
                      _isSignIn ? '02' : '03',
                      style: AppTextStyles.display(160).copyWith(
                          color: const Color(0xFF0E0E0E),
                          height: 0.78,
                          letterSpacing: -0.06 * 160),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(_isSignIn ? 'Returning' : 'New here'),
                      const SizedBox(height: 14),
                      Text(
                        _isSignIn ? 'Sign in to\nyour studio.' : 'Open your\nworkspace.',
                        style: AppTextStyles.display(44)
                            .copyWith(letterSpacing: -0.04 * 44, height: 0.95),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _UnderlineField(
                      label: 'Email',
                      hint: 'you@studio.com',
                      obscure: false,
                      onChanged: (v) => setState(() => _email = v),
                      onFocusChange: (f) => setState(() => _emailFocused = f),
                      focused: _emailFocused,
                    ),
                    const SizedBox(height: 22),
                    _UnderlineField(
                      label: 'Password',
                      hint: '••••••••••',
                      obscure: true,
                      onChanged: (v) => setState(() => _pw = v),
                      onFocusChange: (f) => setState(() => _pwFocused = f),
                      focused: _pwFocused,
                      trailing: Text('Forgot',
                          style: AppTextStyles.mono(9, color: AppColors.muted)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          style: AppTextStyles.body(12,
                              color: AppColors.text.withValues(alpha: 0.7))),
                    ],
                    const SizedBox(height: 36),
                    FillButton(
                      label: _loading
                          ? 'Please wait…'
                          : (_isSignIn ? 'Sign In' : 'Create Account'),
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: AppColors.bg, strokeWidth: 2))
                          : const Icon(Icons.arrow_forward,
                              color: AppColors.bg, size: 18),
                      enabled: _canSubmit,
                      onTap: _submit,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                            child: Container(
                                height: 1,
                                color: AppColors.text.withValues(alpha: 0.15))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text('OR CONTINUE WITH',
                              style: AppTextStyles.mono(9, color: AppColors.faint)),
                        ),
                        Expanded(
                            child: Container(
                                height: 1,
                                color: AppColors.text.withValues(alpha: 0.15))),
                      ],
                    ),
                    const SizedBox(height: 20),
                    OutlineButton(
                      label: 'Continue with Google',
                      icon: const Icon(Icons.g_mobiledata,
                          color: AppColors.text, size: 22),
                      onTap: _loading ? null : _googleSignIn,
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _loading ? null : _setAnon,
                      child: Center(
                        child: Text(
                          'Continue without account →',
                          style: AppTextStyles.body(13,
                              color: AppColors.muted,
                              weight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // footer toggle
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: AppColors.text.withValues(alpha: 0.08))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isSignIn ? 'NEW HERE?' : 'HAVE AN ACCOUNT?',
                    style: AppTextStyles.mono(10, color: AppColors.faint),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _isSignIn = !_isSignIn),
                    child: Row(
                      children: [
                        Text(
                          _isSignIn ? 'Create an account' : 'Sign in instead',
                          style: AppTextStyles.display(14, weight: FontWeight.w600)
                              .copyWith(
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.text),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward,
                            color: AppColors.text, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnderlineField extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onFocusChange;
  final bool focused;
  final Widget? trailing;

  const _UnderlineField({
    required this.label,
    required this.hint,
    required this.obscure,
    required this.onChanged,
    required this.onFocusChange,
    required this.focused,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: onFocusChange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTextStyles.mono(9).copyWith(
                  letterSpacing: 0.28 * 9,
                  color: focused ? AppColors.text : AppColors.muted,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: onChanged,
            obscureText: obscure,
            style: AppTextStyles.body(17),
            cursorColor: AppColors.text,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyles.body(17, color: AppColors.faint),
              border: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: focused
                        ? AppColors.text
                        : AppColors.text.withValues(alpha: 0.25)),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: AppColors.text.withValues(alpha: 0.25)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.text),
              ),
              contentPadding: const EdgeInsets.only(bottom: 8),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}
