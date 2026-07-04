import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_storage.dart';
import '../services/language_levels.dart';
import '../utils/avatar_data.dart';
import 'edit_profile_screen.dart';
import 'help_feedback_screen.dart';
import 'notifications_screen.dart';

// UI languages the app itself can be displayed in — separate from the
// learning-target language picked elsewhere. Only English is selectable for
// now; the rest are shown locked as a preview of what's coming.
const _appLanguages = [
  {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
  {'code': 'pl', 'name': 'Polski', 'flag': '🇵🇱'},
  {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
  {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _openEditProfile() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
    if (mounted) setState(() {});
  }

  void _openNotifications() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  void _openHelpFeedback() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const HelpFeedbackScreen()));
  }

  void _showAppearanceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Appearance',
                  style: GoogleFonts.cormorantGaramond(
                      color: AppColors.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              ...[true, false].map((isDark) {
                final selected = AppStorage.instance.darkMode.value == isDark;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () async {
                      await AppStorage.instance.setDarkMode(isDark);
                      if (!ctx.mounted) return;
                      setSheet(() {});
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primaryGlow : AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color:
                                selected ? AppColors.primary : AppColors.border,
                            width: selected ? 1.5 : 1),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              isDark
                                  ? Icons.dark_mode_outlined
                                  : Icons.light_mode_outlined,
                              size: 20,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.text2),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(isDark ? 'Dark' : 'Light',
                                style: GoogleFonts.dmSans(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                          ),
                          if (selected)
                            Icon(Icons.check_rounded,
                                color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _showAppLanguageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('App language',
                style: GoogleFonts.cormorantGaramond(
                    color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text('Only English is available right now — more are on the way.',
                style: GoogleFonts.dmSans(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 16),
            ..._appLanguages.map((lang) {
              final code = lang['code']!;
              final enabled = code == 'en';
              final selected = AppStorage.instance.appLanguage == code;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: !enabled
                      ? null
                      : () async {
                          await AppStorage.instance.setAppLanguage(code);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                        },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primaryGlow : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: selected ? AppColors.primary : AppColors.border,
                          width: selected ? 1.5 : 1),
                    ),
                    child: Row(
                      children: [
                        Text(lang['flag']!, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(lang['name']!,
                              style: GoogleFonts.dmSans(
                                  color: enabled
                                      ? (selected
                                          ? AppColors.primary
                                          : AppColors.text)
                                      : AppColors.text3,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500)),
                        ),
                        if (selected)
                          Icon(Icons.check_rounded,
                              color: AppColors.primary, size: 20)
                        else if (!enabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text('Coming soon',
                                style: GoogleFonts.dmSans(
                                    color: AppColors.text3, fontSize: 10)),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _confirmLogout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Log out?',
              style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your progress is saved. You can log back in anytime.',
              style: GoogleFonts.dmSans(
                color: AppColors.text2,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text('Cancel', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      AppStorage.instance.clearAll();
                      Navigator.pop(context);
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/auth', (_) => false);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3A1A1A),
                      foregroundColor: const Color(0xFFFF6B6B),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text('Log out', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppStorage.instance.darkMode.value;
    final appLangName = _appLanguages
        .firstWhere((l) => l['code'] == AppStorage.instance.appLanguage,
            orElse: () => _appLanguages.first)['name'];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 20),
            _buildTalutalu(),
            const SizedBox(height: 20),
            _buildHeader(),
            const SizedBox(height: 28),
            _buildStats(),
            const SizedBox(height: 32),
            _buildLevels(),
            _buildSection('Account', [
              _buildTile(
                icon: Icons.person_outline_rounded,
                label: 'Edit profile',
                onTap: _openEditProfile,
              ),
              _buildTile(
                icon: Icons.language_rounded,
                label: 'App language',
                trailing: Text(
                  appLangName ?? 'English',
                  style: GoogleFonts.dmSans(color: AppColors.text2, fontSize: 14),
                ),
                onTap: _showAppLanguageSheet,
              ),
            ]),
            const SizedBox(height: 20),
            _buildSection('App', [
              _buildTile(
                icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                label: 'Appearance',
                trailing: Text(
                  isDark ? 'Dark' : 'Light',
                  style: GoogleFonts.dmSans(color: AppColors.text2, fontSize: 14),
                ),
                onTap: _showAppearanceSheet,
              ),
              _buildTile(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                onTap: _openNotifications,
              ),
              _buildTile(
                icon: Icons.help_outline_rounded,
                label: 'Help & feedback',
                onTap: _openHelpFeedback,
              ),
            ]),
            const SizedBox(height: 20),
            _buildSection('', [
              _buildTile(
                icon: Icons.logout_rounded,
                label: 'Log out',
                labelColor: const Color(0xFFFF6B6B),
                iconColor: const Color(0xFFFF6B6B),
                onTap: () => _confirmLogout(context),
              ),
            ]),
            const SizedBox(height: 40),
            Center(
              child: Text(
                'Talutalu v1.0.0',
                style: GoogleFonts.dmSans(color: AppColors.text3, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTalutalu() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('talutalu',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 26,
                fontWeight: FontWeight.w300,
                letterSpacing: -0.8)),
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(bottom: 5, left: 2),
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.6),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final name = AppStorage.instance.userName;
    final avatarIndex = AppStorage.instance.selectedAvatar;

    return Row(
      children: [
        _buildAvatarWidget(avatarIndex, name),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            name.isNotEmpty ? name : 'User',
            style: GoogleFonts.cormorantGaramond(
              color: AppColors.text,
              fontSize: 28,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarWidget(int? avatarIndex, String name) {
    if (avatarIndex != null && avatarIndex < allAvatars.length) {
      final city = allAvatars[avatarIndex];
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: city.svgPath != null
            ? SvgPicture.asset(city.svgPath!, width: 72, height: 72)
            : Container(
                width: 72,
                height: 72,
                color: city.backgroundColor,
                child: Center(
                  child: Text(city.flag,
                      style: const TextStyle(fontSize: 34)),
                ),
              ),
      );
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C5CFC), Color(0xFF4F35C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.cormorantGaramond(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildLevels() {
    final levels = computeLanguageLevels();
    if (levels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('LEVELS',
                style: GoogleFonts.dmSans(
                    color: AppColors.text3,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: List.generate(levels.length, (i) {
                return Column(
                  children: [
                    _buildLevelRow(levels[i]),
                    if (i < levels.length - 1)
                      Divider(
                          height: 1,
                          thickness: 0.5,
                          color: AppColors.border,
                          indent: 16),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelRow(LanguageLevel lang) {
    final level = lang.level;
    final base = cumulativeForLevel(level);
    final next = cumulativeForLevel(level + 1);
    final into = lang.points - base;
    final needed = next - base;
    final progress = needed == 0 ? 0.0 : into / needed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(lang.targetFlag, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(lang.targetName,
                    style: GoogleFonts.dmSans(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Text('Lvl $level',
                    style: GoogleFonts.dmSans(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStat('12', 'Day streak', Icons.local_fire_department_rounded, const Color(0xFFFF8C42)),
          _buildDivider(),
          _buildStat('248', 'Words', Icons.style_rounded, AppColors.primary),
          _buildDivider(),
          _buildStat('4', 'Texts read', Icons.menu_book_rounded, const Color(0xFF4CAF82)),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.cormorantGaramond(
            color: AppColors.text,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.dmSans(
            color: AppColors.text2,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 48, color: AppColors.border);
  }

  Widget _buildSection(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: List.generate(tiles.length, (i) {
              return Column(
                children: [
                  tiles[i],
                  if (i < tiles.length - 1)
                    Divider(height: 1, thickness: 0.5, color: AppColors.border, indent: 52),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    Color? labelColor,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? AppColors.text2, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  color: labelColor ?? AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 6),
            ],
            if (trailing == null && labelColor == null)
              Icon(Icons.chevron_right_rounded, color: AppColors.text3, size: 20),
          ],
        ),
      ),
    );
  }
}
