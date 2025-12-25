// lib/common/ui_bits.dart

import 'package:flutter/material.dart';

// Defined the theme's dark blue color (0xFF180D3B) based on theme.dart
const _kThemeBlue = Color(0xFF180D3B); 


/// Bold mini section header
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      );
}

/// Card container with soft shadow and rounded corners
class UiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const UiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 16),
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8)),
          ],
        ),
        padding: padding,
        child: child,
      );
}

/// A standard label shown above an input field.
/// NOTE: The original Labeled widget (without icon) is removed,
/// and this new, more complex LabeledField is introduced.
class LabeledField extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  
  const LabeledField({
    super.key,
    required this.label,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label, style: labelStyle),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}


/// Tiny label shown above any input (The original, simpler Labeled widget)
// Renaming the original Labeled widget to LabeledSimple to avoid conflict, 
// but keeping the core component structure.
class LabeledSimple extends StatelessWidget {
  final String label;
  final Widget child;
  const LabeledSimple({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      );
}

/// Rounded “pill” action (used for date/time pickers)
class PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool clearable;
  final VoidCallback? onClear;

  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.clearable = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (clearable)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 18, color: Colors.black45),
                  tooltip: 'Clear',
                ),
            ],
          ),
        ),
      );
}

/// Small circular +/− button used in seat steppers
class CircleBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const CircleBtn({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFEAEAF4) : Colors.black12,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? const Color(0xFF1A1452) : Colors.black38,
          ),
        ),
      );
}