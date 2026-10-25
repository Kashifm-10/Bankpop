import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

/// One board in a picker: its flag (or an icon for a player's own board) and
/// its name, with the selected one filled in so a row of them reads as a
/// choice rather than a list.
class CountryChip extends StatelessWidget {
  const CountryChip({
    super.key,
    required this.label,
    this.flag = '',
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String flag;

  /// Shown instead of [flag], for a board that has no flag of its own.
  final IconData? icon;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData? icon = this.icon;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFC5E1A5) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF689F38) : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (flag.isNotEmpty)
              Text(flag, style: const TextStyle(fontSize: 14))
            else if (icon != null)
              Icon(
                icon,
                size: 14,
                color: selected ? const Color(0xFF2E7D32) : Colors.black54,
              ),
            if (flag.isNotEmpty || icon != null) const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? const Color(0xFF2E7D32) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
