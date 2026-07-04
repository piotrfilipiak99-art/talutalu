import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_storage.dart';
import '../utils/avatar_data.dart';
import 'language_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  // Page 0 — avatar
  int? _selectedAvatarIndex;
  String _avatarSearch = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // Page 1 — personal
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _hobbyCtrl = TextEditingController();

  // Page 2 — language
  bool _hasCourse = false;
  List<Map<String, String>> _pickerBases = [];
  List<Map<String, String>> _pickerCourses = [];
  String? _pickerSelectedBase;
  Map<String, String>? _pickerActiveCourse;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _hobbyCtrl.dispose();
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _fadeCtrl.reverse().then((_) {
        _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
        setState(() => _currentPage++);
        _fadeCtrl.forward();
      });
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    if (_selectedAvatarIndex != null) {
      await AppStorage.instance.saveAvatar(_selectedAvatarIndex!);
    }
    await AppStorage.instance.saveProfile(
      _nameCtrl.text.trim(),
      _hobbyCtrl.text.trim(),
    );
    await AppStorage.instance.saveCourseState(
      bases: _pickerBases,
      courses: _pickerCourses,
      selectedBase: _pickerSelectedBase,
      activeCourse: _pickerActiveCourse,
    );
    await AppStorage.instance.setLoggedIn(true);
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  bool get _canContinue {
    switch (_currentPage) {
      case 0:
        return _selectedAvatarIndex != null;
      case 1:
        return _nameCtrl.text.trim().isNotEmpty &&
            _hobbyCtrl.text.trim().isNotEmpty;
      case 2:
        return _hasCourse;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildAvatarPage(),
                  _buildPersonalPage(),
                  _buildLanguagePage(),
                ],
              ),
            ),
            _buildContinueButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: List.generate(3, (i) {
          final active = i <= _currentPage;
          return Expanded(
            child: Container(
              height: 2,
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Page 0: Avatar ──────────────────────────────────────────────────────────

  Widget _buildAvatarCircle(AvatarCity city, double size) {
    if (city.svgPath != null) {
      return SvgPicture.asset(city.svgPath!, width: size, height: size);
    }
    return Container(
      width: size,
      height: size,
      color: city.backgroundColor,
      child: Center(
        child: Text(city.flag, style: TextStyle(fontSize: size * 0.44)),
      ),
    );
  }

  Widget _buildAvatarPage() {
    final q = _avatarSearch.toLowerCase();
    final indices = q.isEmpty
        ? List.generate(allAvatars.length, (i) => i)
        : [
            for (int i = 0; i < allAvatars.length; i++)
              if (allAvatars[i].name.toLowerCase().contains(q) ||
                  allAvatars[i].country.toLowerCase().contains(q))
                i,
          ];

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 56, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose your\navatar.',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Pick a city that speaks to you.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _avatarSearch = v),
                  decoration: InputDecoration(
                    hintText: 'Search city or country…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _avatarSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _avatarSearch = '');
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 110,
              ),
              itemCount: indices.length,
              itemBuilder: (_, fi) {
                final i = indices[fi];
                final city = allAvatars[i];
                final isSelected = _selectedAvatarIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatarIndex = i),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 14,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipOval(
                          child: _buildAvatarCircle(city, 72),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        city.name,
                        style: GoogleFonts.dmSans(
                          color: isSelected
                              ? AppColors.primarySoft
                              : AppColors.text2,
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        city.country,
                        style: GoogleFonts.dmSans(
                          color: AppColors.text3,
                          fontSize: 9,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 1: Personal ────────────────────────────────────────────────────────

  Widget _buildPersonalPage() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 56),
            Text(
              'Tell us about\nyourself.',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'We\'ll personalize your reading experience.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 48),
            Text(
              'NAME',
              style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              autofocus: false,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.dmSans(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: 'Your name',
                suffixIcon: _nameCtrl.text.isNotEmpty
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 20)
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'HOBBIES & INTERESTS',
              style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _hobbyCtrl,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.dmSans(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. cooking, hiking, jazz…',
                suffixIcon: _hobbyCtrl.text.isNotEmpty
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 20)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Used to generate reading texts you\'ll actually enjoy.',
              style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Page 2: Language ────────────────────────────────────────────────────────

  Widget _buildLanguagePage() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 56),
            Text(
              'What do you\nwant to learn?',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Add your first course to get started.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 36),
            LanguagePickerContent(
              onCoursesChanged: (courses) =>
                  setState(() => _hasCourse = courses.isNotEmpty),
              onStateChanged: (bases, courses, selectedBase, activeCourse) {
                _pickerBases = List.from(bases);
                _pickerCourses = List.from(courses);
                _pickerSelectedBase = selectedBase;
                _pickerActiveCourse = activeCourse;
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Continue button ─────────────────────────────────────────────────────────

  Widget _buildContinueButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AnimatedOpacity(
        opacity: _canContinue ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _canContinue ? _nextPage : null,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              _currentPage < 2 ? 'Continue' : 'Get Started',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
