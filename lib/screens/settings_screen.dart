import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _analytics = false;
  bool _haptics = true;
  bool _autoSave = true;
  bool _grain = true;
  String? _toast;
  int _localCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final n = await HistoryService.instance.localCount();
    if (mounted) setState(() => _localCount = n);
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _onTabTap(int i) {
    if (i == 0) context.go('/home');
    if (i == 1) context.go('/history');
  }

  Future<void> _clearHistory() async {
    await HistoryService.instance.clearHistory();
    ref.invalidate(historyProvider);
    await _loadCount();
    _showToast('History cleared');
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    ref.read(isAuthenticatedProvider.notifier).state = false;
    ref.read(isAnonymousProvider.notifier).state = true;
    if (mounted) context.go('/');
  }

  String get _displayName {
    if (AuthService.instance.isAnonymousSession) return 'Anonymous';
    return AuthService.instance.displayName ?? 'User';
  }

  String get _displayEmail {
    if (AuthService.instance.isAnonymousSession) return 'No account — local only';
    return AuthService.instance.email ?? '';
  }

  String get _initials {
    if (AuthService.instance.isAnonymousSession) return '?';
    return AuthService.instance.initials;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Preferences'),
                      const SizedBox(height: 8),
                      Text('Settings',
                          style: AppTextStyles.display(38,
                              weight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  children: [
                    // Profile card
                    Container(
                      padding: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: AppColors.text.withValues(alpha: 0.1))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.text),
                            ),
                            alignment: Alignment.center,
                            child: Text(_initials,
                                style: AppTextStyles.body(18,
                                    weight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_displayName,
                                    style: AppTextStyles.body(16,
                                        weight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text(_displayEmail,
                                    style: AppTextStyles.mono(11,
                                        color: AppColors.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    _Section(
                      title: 'General',
                      children: [
                        _ToggleRow(
                          label: 'Auto-save outputs',
                          sub: 'Save processed files automatically',
                          value: _autoSave,
                          onChanged: (v) => setState(() => _autoSave = v),
                        ),
                        _ToggleRow(
                          label: 'Haptic feedback',
                          sub: 'Subtle taps on actions',
                          value: _haptics,
                          onChanged: (v) => setState(() => _haptics = v),
                        ),
                        _ToggleRow(
                          label: 'Grain texture',
                          sub: 'Editorial film grain on splash',
                          value: _grain,
                          onChanged: (v) => setState(() => _grain = v),
                        ),
                      ],
                    ),

                    _Section(
                      title: 'Privacy',
                      children: [
                        _ToggleRow(
                          label: 'Anonymous analytics',
                          sub: 'Share crash reports only',
                          value: _analytics,
                          onChanged: (v) => setState(() => _analytics = v),
                        ),
                        SettingsRow(
                          label: 'Clear history',
                          detail: '$_localCount files',
                          onTap: _clearHistory,
                        ),
                      ],
                    ),

                    _Section(
                      title: 'About',
                      children: [
                        const SettingsRow(
                            label: 'Version', detail: '1.0.0 · build 1'),
                        const SettingsRow(label: 'Open source licenses'),
                        const SettingsRow(label: 'Privacy policy'),
                      ],
                    ),

                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _signOut,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.text),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text('Sign Out',
                            style: AppTextStyles.body(14,
                                weight: FontWeight.w500)),
                      ),
                    ),

                    const SizedBox(height: 32),
                    Center(
                      child: Text(
                        'PDFist · MADE TO BE QUIET',
                        style: AppTextStyles.mono(9,
                            color: AppColors.text.withValues(alpha: 0.3)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              AppBottomNav(currentIndex: 2, onTap: _onTabTap),
            ],
          ),
          ToastOverlay(message: _toast),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 10),
            child: Eyebrow(title),
          ),
          Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line))),
            child: Column(children: children),
          ),
        ],
      );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow(
      {required this.label,
      required this.sub,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: AppTextStyles.body(14,
                            weight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: AppTextStyles.body(12,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              AppToggle(value: value, onChanged: onChanged),
            ],
          ),
        ),
      );
}
