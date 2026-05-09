import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ── Status bar spacer (just top padding under system bar)
class StatusBarSpacer extends StatelessWidget {
  const StatusBarSpacer({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(height: MediaQuery.of(context).padding.top);
}

// ── Eyebrow label
class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTextStyles.eyebrow,
      );
}

// ── Mono label
class MonoText extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  const MonoText(this.text, {super.key, this.size = 10, this.color});
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTextStyles.mono(size, color: color ?? AppColors.faint),
      );
}

// ── Chip
class AppChip extends StatelessWidget {
  final String label;
  const AppChip(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.text),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(label.toUpperCase(), style: AppTextStyles.chip.copyWith(fontSize: 9)),
      );
}

// ── Fill button (white bg, black text)
class FillButton extends StatelessWidget {
  final String label;
  final Widget? icon;
  final VoidCallback? onTap;
  final bool enabled;
  const FillButton({super.key, required this.label, this.icon, this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1.0 : 0.3,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.text,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: AppTextStyles.body(15, weight: FontWeight.w600, color: AppColors.bg)),
              if (icon != null) ...[const SizedBox(width: 10), icon!],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Outline button (black bg, white border)
class OutlineButton extends StatelessWidget {
  final String label;
  final Widget? icon;
  final VoidCallback? onTap;
  const OutlineButton({super.key, required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border.all(color: AppColors.text),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 10)],
              Text(label, style: AppTextStyles.body(15, weight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

// ── Toggle
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppToggle({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged?.call(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 26,
          decoration: BoxDecoration(
            color: value ? AppColors.text : AppColors.bg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.text),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? AppColors.bg : AppColors.text,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
}

// ── Divider hairline
class HairlineDivider extends StatelessWidget {
  const HairlineDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(height: 1, color: AppColors.line);
}

// ── Bottom nav
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
        height: 76,
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.text, width: 1)),
        ),
        child: Row(
          children: [
            _NavItem(icon: Icons.home_outlined, label: 'Home', active: currentIndex == 0, onTap: () => onTap(0)),
            _NavItem(icon: Icons.history, label: 'History', active: currentIndex == 1, onTap: () => onTap(1)),
            _NavItem(icon: Icons.settings_outlined, label: 'Settings', active: currentIndex == 2, onTap: () => onTap(2)),
          ],
        ),
      );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (active)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
                )
              else
                const SizedBox(height: 8),
              Icon(icon, color: active ? AppColors.text : AppColors.muted, size: 20),
              const SizedBox(height: 4),
              Text(
                label.toUpperCase(),
                style: AppTextStyles.body(10,
                    weight: FontWeight.w500,
                    color: active ? AppColors.text : AppColors.muted),
              ),
            ],
          ),
        ),
      );
}

// ── Arrow icon painter (line icon)
class ArrowRight extends StatelessWidget {
  final double size;
  final Color color;
  const ArrowRight({super.key, this.size = 16, this.color = AppColors.text});
  @override
  Widget build(BuildContext context) => Icon(Icons.arrow_forward, size: size, color: color);
}

// ── Toast overlay
class ToastOverlay extends StatelessWidget {
  final String? message;
  const ToastOverlay({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border.all(color: AppColors.text),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check, color: AppColors.text, size: 16),
              const SizedBox(width: 10),
              Text(message!, style: AppTextStyles.body(13, weight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── File thumbnail (shows extension label, defaults to PDF)
class PdfFileThumbnail extends StatelessWidget {
  final String label;
  const PdfFileThumbnail({super.key, this.label = 'PDF'});
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 56,
        decoration: BoxDecoration(border: Border.all(color: AppColors.text), borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(4),
        child: Text(label.toUpperCase(), style: AppTextStyles.mono(8, color: AppColors.text)),
      );
}

// ── Section header for tool lists
class SectionHeader extends StatelessWidget {
  final String title;
  final String? count;
  const SectionHeader({super.key, required this.title, this.count});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.text)),
        ),
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title.toUpperCase(),
              style: AppTextStyles.body(11, weight: FontWeight.w600).copyWith(letterSpacing: 1.65),
            ),
            if (count != null)
              Text(count!, style: AppTextStyles.mono(10, color: AppColors.faint)),
          ],
        ),
      );
}

// ── Row item for settings/lists with chevron
class SettingsRow extends StatelessWidget {
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  const SettingsRow({super.key, required this.label, this.detail, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.body(14, weight: FontWeight.w500))),
              if (detail != null) ...[
                Text(detail!, style: AppTextStyles.mono(12, color: AppColors.muted)),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: AppColors.muted, size: 16),
            ],
          ),
        ),
      );
}
