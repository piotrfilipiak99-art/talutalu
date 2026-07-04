import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Full-screen celebration shown when practicing pushes a language over a
/// level threshold. Pops in with an elastic scale, radiates a burst of rays
/// behind the flag, and always names the language the level was earned in.
Future<void> showLevelUpCelebration(
  BuildContext context, {
  required String languageName,
  required String languageFlag,
  required int level,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Level up',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, _, _) => _LevelUpCelebration(
      languageName: languageName,
      languageFlag: languageFlag,
      level: level,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final scale = CurvedAnimation(
          parent: anim,
          curve: Curves.elasticOut,
          reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: scale, child: child),
      );
    },
  );
}

class _LevelUpCelebration extends StatefulWidget {
  final String languageName;
  final String languageFlag;
  final int level;
  const _LevelUpCelebration({
    required this.languageName,
    required this.languageFlag,
    required this.level,
  });

  @override
  State<_LevelUpCelebration> createState() => _LevelUpCelebrationState();
}

class _LevelUpCelebrationState extends State<_LevelUpCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rays;

  @override
  void initState() {
    super.initState();
    _rays = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _rays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 36),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _rays,
                      builder: (_, _) => Transform.rotate(
                        angle: _rays.value * 2 * math.pi,
                        child: CustomPaint(
                          size: const Size(120, 120),
                          painter: _RaysPainter(
                              color:
                                  AppColors.primary.withValues(alpha: 0.25)),
                        ),
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGlow,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Center(
                        child: Text(widget.languageFlag,
                            style: const TextStyle(fontSize: 34)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('LEVEL UP',
                  style: GoogleFonts.dmSans(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              Text('${widget.languageName} · Level ${widget.level}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cormorantGaramond(
                      color: AppColors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      height: 1.1)),
              const SizedBox(height: 10),
              Text(
                'You reached level ${widget.level} in '
                '${widget.languageName}. Keep it up!',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    color: AppColors.text2, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text('Continue',
                      style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ring of soft triangular rays radiating from the center — rotated as a
/// whole by the looping controller above for a subtle sunburst effect.
class _RaysPainter extends CustomPainter {
  final Color color;
  const _RaysPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final inner = size.width * 0.32;
    final outer = size.width * 0.5;
    final paint = Paint()..color = color;
    const rayCount = 12;
    for (var i = 0; i < rayCount; i++) {
      final angle = i * 2 * math.pi / rayCount;
      const halfWidth = math.pi / rayCount * 0.45;
      final path = Path()
        ..moveTo(center.dx + inner * math.cos(angle - halfWidth),
            center.dy + inner * math.sin(angle - halfWidth))
        ..lineTo(center.dx + outer * math.cos(angle),
            center.dy + outer * math.sin(angle))
        ..lineTo(center.dx + inner * math.cos(angle + halfWidth),
            center.dy + inner * math.sin(angle + halfWidth))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter oldDelegate) =>
      oldDelegate.color != color;
}
