import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

const availableLanguages = [
  {'code': 'pl', 'name': 'Polish', 'native': 'Polski', 'flag': '🇵🇱'},
  {'code': 'en', 'name': 'English', 'native': 'English', 'flag': '🇬🇧'},
  {'code': 'es', 'name': 'Spanish', 'native': 'Español', 'flag': '🇪🇸'},
  {'code': 'fr', 'name': 'French', 'native': 'Français', 'flag': '🇫🇷'},
  {'code': 'de', 'name': 'German', 'native': 'Deutsch', 'flag': '🇩🇪'},
  {'code': 'it', 'name': 'Italian', 'native': 'Italiano', 'flag': '🇮🇹'},
  {'code': 'pt', 'name': 'Portuguese', 'native': 'Português', 'flag': '🇵🇹'},
  {'code': 'ru', 'name': 'Russian', 'native': 'Русский', 'flag': '🇷🇺'},
  {'code': 'uk', 'name': 'Ukrainian', 'native': 'Українська', 'flag': '🇺🇦'},
  {'code': 'ja', 'name': 'Japanese', 'native': '日本語', 'flag': '🇯🇵'},
  {'code': 'ko', 'name': 'Korean', 'native': '한국어', 'flag': '🇰🇷'},
  {'code': 'zh', 'name': 'Chinese', 'native': '中文', 'flag': '🇨🇳'},
  {'code': 'ar', 'name': 'Arabic', 'native': 'العربية', 'flag': '🇸🇦'},
  {'code': 'nl', 'name': 'Dutch', 'native': 'Nederlands', 'flag': '🇳🇱'},
  {'code': 'sv', 'name': 'Swedish', 'native': 'Svenska', 'flag': '🇸🇪'},
  {'code': 'tr', 'name': 'Turkish', 'native': 'Türkçe', 'flag': '🇹🇷'},
  {'code': 'cs', 'name': 'Czech', 'native': 'Čeština', 'flag': '🇨🇿'},
  {'code': 'el', 'name': 'Greek', 'native': 'Ελληνικά', 'flag': '🇬🇷'},
  {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी', 'flag': '🇮🇳'},
];

const baseLanguages = [
  {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
  {'code': 'de', 'name': 'German', 'flag': '🇩🇪'},
  {'code': 'es', 'name': 'Spanish', 'flag': '🇪🇸'},
  {'code': 'fr', 'name': 'French', 'flag': '🇫🇷'},
  {'code': 'it', 'name': 'Italian', 'flag': '🇮🇹'},
  {'code': 'pt', 'name': 'Portuguese', 'flag': '🇵🇹'},
  {'code': 'ru', 'name': 'Russian', 'flag': '🇷🇺'},
  {'code': 'uk', 'name': 'Ukrainian', 'flag': '🇺🇦'},
];

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text('Your\nlanguages.',
                  style: Theme.of(context).textTheme.displayMedium),
              const SizedBox(height: 10),
              Text('Add a language to start learning.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 32),
              LanguagePickerContent(onCoursesChanged: (_) {}),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguagePickerContent extends StatefulWidget {
  final void Function(List<Map<String, String>> courses) onCoursesChanged;
  final void Function(
    List<Map<String, String>> bases,
    List<Map<String, String>> courses,
    String? selectedBase,
    Map<String, String>? activeCourse,
  )? onStateChanged;
  final void Function(Map<String, String> course)? onCourseTapped;
  final List<Map<String, String>> initialBases;
  final List<Map<String, String>> initialCourses;
  final String? initialSelectedBase;
  final Map<String, String>? initialActiveCourse;

  const LanguagePickerContent({
    super.key,
    required this.onCoursesChanged,
    this.onStateChanged,
    this.onCourseTapped,
    this.initialBases = const [],
    this.initialCourses = const [],
    this.initialSelectedBase,
    this.initialActiveCourse,
  });

  @override
  State<LanguagePickerContent> createState() => _LanguagePickerContentState();
}

class _LanguagePickerContentState extends State<LanguagePickerContent> {
  late List<Map<String, String>> _bases;
  late List<Map<String, String>> _courses;
  late String? _selectedBaseCode;
  late Map<String, String>? _activeCourse;

  @override
  void initState() {
    super.initState();
    _bases = List.from(widget.initialBases);
    _courses = List.from(widget.initialCourses);
    _selectedBaseCode = widget.initialSelectedBase;
    _activeCourse = widget.initialActiveCourse;
  }

  void _notify() {
    widget.onStateChanged?.call(_bases, _courses, _selectedBaseCode, _activeCourse);
  }

  List<Map<String, String>> get _activeCourses => _selectedBaseCode == null
      ? []
      : _courses.where((c) => c['baseCode'] == _selectedBaseCode).toList();

  // ── Add base language ──────────────────────────────────────────────────────

  void _showAddBaseSheet() {
    final available = baseLanguages
        .where((b) => !_bases.any((a) => a['code'] == b['code']))
        .toList();
    if (available.isEmpty) return;

    String? tempBase;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _handle(),
                const SizedBox(height: 24),
                Text(
                  'I already speak…',
                  style: GoogleFonts.cormorantGaramond(
                    color: AppColors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add a language you know.',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text2, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: available.map((base) {
                    final selected = tempBase == base['code'];
                    return GestureDetector(
                      onTap: () => setSheet(() => tempBase = base['code']),
                      child: _chip(
                        flag: base['flag']!,
                        name: base['name']!,
                        selected: selected,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                _confirmButton(
                  label: 'Add',
                  enabled: tempBase != null,
                  onTap: () {
                    final base = baseLanguages
                        .firstWhere((b) => b['code'] == tempBase);
                    setState(() {
                      _bases.add(Map.from(base));
                      _selectedBaseCode ??= base['code'];
                    });
                    _notify();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Add course ─────────────────────────────────────────────────────────────

  void _showAddCourseSheet() {
    if (_selectedBaseCode == null) return;

    final base = _bases.firstWhere((b) => b['code'] == _selectedBaseCode);
    final alreadyAdded = _courses
        .where((c) => c['baseCode'] == _selectedBaseCode)
        .map((c) => c['targetCode'])
        .toSet();

    String? tempTarget;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _handle(),
                const SizedBox(height: 24),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.cormorantGaramond(
                      color: AppColors.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      const TextSpan(text: 'Learn in '),
                      TextSpan(
                        text: '${base['flag']} ${base['name']}',
                        style: TextStyle(color: AppColors.primarySoft),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a language you want to learn.',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text2, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableLanguages.map((lang) {
                    final selected = tempTarget == lang['code'];
                    final added = alreadyAdded.contains(lang['code']);
                    return GestureDetector(
                      onTap: added
                          ? null
                          : () => setSheet(() => tempTarget = lang['code']),
                      child: _chip(
                        flag: lang['flag']!,
                        name: lang['name']!,
                        selected: selected,
                        dimmed: added,
                        suffix: added ? 'added' : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                _confirmButton(
                  label: 'Add course',
                  enabled: tempTarget != null,
                  onTap: () {
                    final target = availableLanguages
                        .firstWhere((l) => l['code'] == tempTarget);
                    final newCourse = {
                      'targetCode': target['code']!,
                      'targetName': target['name']!,
                      'targetFlag': target['flag']!,
                      'baseCode': base['code']!,
                      'baseName': base['name']!,
                      'baseFlag': base['flag']!,
                    };
                    setState(() {
                      _courses.add(newCourse);
                      _activeCourse = newCourse;
                    });
                    widget.onCoursesChanged(_courses);
                    _notify();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _handle() => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _chip({
    required String flag,
    required String name,
    required bool selected,
    bool dimmed = false,
    String? suffix,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primaryGlow
            : dimmed
                ? AppColors.surface
                : AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            name,
            style: GoogleFonts.dmSans(
              color: dimmed
                  ? AppColors.text3
                  : selected
                      ? AppColors.primarySoft
                      : AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 6),
            Text(suffix,
                style: GoogleFonts.dmSans(
                    color: AppColors.text3, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _confirmButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFromSection(),
        const SizedBox(height: 28),
        _buildCoursesGrid(),
      ],
    );
  }

  Widget _buildFromSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FROM',
          style: GoogleFonts.dmSans(
            color: AppColors.text3,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._bases.map((lang) {
              final active = _selectedBaseCode == lang['code'];
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedBaseCode = lang['code']);
                  _notify();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primaryGlow : AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(lang['flag']!,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        lang['name']!,
                        style: GoogleFonts.dmSans(
                          color: active
                              ? AppColors.primarySoft
                              : AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            // Add base language chip
            if (_bases.length < baseLanguages.length)
              GestureDetector(
                onTap: _showAddBaseSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 14, color: AppColors.text3),
                      const SizedBox(width: 4),
                      Text(
                        'Add',
                        style: GoogleFonts.dmSans(
                          color: AppColors.text3,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoursesGrid() {
    if (_selectedBaseCode == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TO',
            style: GoogleFonts.dmSans(
              color: AppColors.text3,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Add a language above to see courses.',
            style: GoogleFonts.dmSans(color: AppColors.text3, fontSize: 13),
          ),
        ],
      );
    }

    final courses = _activeCourses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TO',
          style: GoogleFonts.dmSans(
            color: AppColors.text3,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: courses.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            mainAxisExtent: 128,
          ),
          itemBuilder: (_, i) {
            if (i == courses.length) return _buildAddCourseTile();
            return _buildCourseTile(courses[i]);
          },
        ),
      ],
    );
  }

  Widget _buildCourseTile(Map<String, String> course) {
    final isActive = _activeCourse?['targetCode'] == course['targetCode'] &&
        _activeCourse?['baseCode'] == course['baseCode'];
    return GestureDetector(
      onTap: () {
        setState(() => _activeCourse = course);
        widget.onCourseTapped?.call(course);
        _notify();
      },
      child: _buildCourseTileContent(course, isActive),
    );
  }

  Widget _buildCourseTileContent(Map<String, String> course, bool isActive) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primaryGlow : AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? AppColors.primary : AppColors.border,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(course['targetFlag']!,
                  style: const TextStyle(fontSize: 38)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          course['targetName']!,
          style: GoogleFonts.dmSans(
            color: isActive ? AppColors.primarySoft : AppColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'from ${course['baseName']}',
          style: GoogleFonts.dmSans(color: AppColors.text3, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildAddCourseTile() {
    return GestureDetector(
      onTap: _showAddCourseSheet,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Icon(Icons.add_rounded,
                    color: AppColors.text3, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add',
            style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 11),
        ],
      ),
    );
  }
}
