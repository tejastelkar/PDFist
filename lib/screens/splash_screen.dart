import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/app_config.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Brief delay so the splash is visible.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    if (kFirebaseEnabled) {
      final user = AuthService.instance.currentUser;
      if (user != null) {
        ref.read(isAuthenticatedProvider.notifier).state = true;
        ref.read(isAnonymousProvider.notifier).state = false;
        if (mounted) context.go('/home');
        return;
      }
    }
    // No persisted session — go to auth.
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('EST · 2026', style: AppTextStyles.mono(10, color: AppColors.faint)),
                      Text('v1.0', style: AppTextStyles.mono(10, color: AppColors.faint)),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Eyebrow('An offline PDF toolkit'),
                        const SizedBox(height: 28),
                        Text(
                          'PDFist',
                          style: AppTextStyles.display(76)
                              .copyWith(letterSpacing: -0.05 * 76, height: 0.85),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        Container(
                            width: 64, height: 1, color: AppColors.text.withValues(alpha: 0.6)),
                        const SizedBox(height: 24),
                        Text(
                          'Every PDF action.\nZero cloud.',
                          style: AppTextStyles.body(17,
                              color: AppColors.text.withValues(alpha: 0.85)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: Column(
                      children: [
                        FillButton(
                          label: 'Get Started',
                          icon: const Icon(Icons.arrow_forward,
                              color: AppColors.bg, size: 18),
                          onTap: () => context.go('/auth'),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('NO ACCOUNT REQUIRED',
                                style: AppTextStyles.mono(10, color: AppColors.faint)),
                            Text('—',
                                style: AppTextStyles.mono(10, color: AppColors.faint)),
                            Text('FILES STAY LOCAL',
                                style: AppTextStyles.mono(10, color: AppColors.faint)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
