import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class CourseBadge extends StatelessWidget {
  final Map<String, String>? course;
  final VoidCallback onTap;

  const CourseBadge({super.key, required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = course;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c != null) ...[
              Text(c['baseFlag'] ?? '',
                  style: const TextStyle(fontSize: 15, height: 1)),
              const SizedBox(width: 3),
              Icon(Icons.arrow_forward_rounded,
                  size: 11, color: AppColors.text3),
              const SizedBox(width: 3),
              Text(c['targetFlag'] ?? '',
                  style: const TextStyle(fontSize: 15, height: 1)),
              const SizedBox(width: 6),
              Text(
                c['targetName'] ?? '',
                style: GoogleFonts.dmSans(
                    color: AppColors.text2,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ] else
              Text('Select course',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text3, fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded,
                size: 16, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}
