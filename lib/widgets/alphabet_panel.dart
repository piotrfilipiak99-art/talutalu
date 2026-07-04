import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/alphabet_data.dart';
import '../services/app_storage.dart';
import '../theme/app_theme.dart';


class AlphabetPanel extends StatefulWidget {
  const AlphabetPanel({super.key});

  @override
  State<AlphabetPanel> createState() => _AlphabetPanelState();
}

class _AlphabetPanelState extends State<AlphabetPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _sizeFactor;

  bool _expanded = false;
  int _groupIndex = 0;
  LanguageAlphabet? _alphabet;

  final FlutterTts _tts = FlutterTts();
  String? _speakingChar;

  List<AlphabetGroup> get _visibleGroups => _alphabet?.groups ?? [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _sizeFactor = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _reload();
    AppStorage.instance.courseChanged.addListener(_reload);
  }

  @override
  void dispose() {
    AppStorage.instance.courseChanged.removeListener(_reload);
    _ctrl.dispose();
    _tts.stop();
    super.dispose();
  }

  void _reload() {
    final course = AppStorage.instance.activeCourse;
    if (!mounted) return;
    final newAlphabet =
        course == null ? null : alphabetFor(course['targetCode'] ?? '');
    setState(() {
      _alphabet = newAlphabet;
      _groupIndex = 0;
      if (_expanded && _visibleGroups.isEmpty) {
        _expanded = false;
        _ctrl.reverse();
      }
    });
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  Future<void> _speak(AlphabetEntry entry) async {
    final text = entry.ttsText ?? entry.name;
    setState(() => _speakingChar = entry.char);
    await _tts.setLanguage(_alphabet!.ttsLocale);
    await _tts.setSpeechRate(0.45);
    await _tts.speak(text);
    if (mounted) setState(() => _speakingChar = null);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _visibleGroups;
    if (groups.isEmpty) return const SizedBox.shrink();

    final safeIndex = _groupIndex.clamp(0, groups.length - 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandle(groups),
        SizeTransition(
          sizeFactor: _sizeFactor,
          axisAlignment: -1,
          child: _buildBody(groups, safeIndex),
        ),
      ],
    );
  }

  Widget _buildHandle(List<AlphabetGroup> groups) {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.translate_rounded,
                size: 15, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: _expanded
                  ? Text(
                      groups.map((g) => g.label).join(' · '),
                      style: GoogleFonts.dmSans(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    )
                  : Text(
                      _alphabet!.nativeName,
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: Icon(Icons.keyboard_arrow_up_rounded,
                  size: 20, color: AppColors.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<AlphabetGroup> groups, int activeIndex) {
    return Container(
      height: 284,
      color: AppColors.surface,
      child: Column(
        children: [
          if (groups.length > 1) _buildGroupTabs(groups, activeIndex),
          Expanded(child: _buildGrid(groups[activeIndex])),
        ],
      ),
    );
  }

  Widget _buildGroupTabs(List<AlphabetGroup> groups, int activeIndex) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: List.generate(groups.length, (i) {
          final active = i == activeIndex;
          return GestureDetector(
            onTap: () => setState(() => _groupIndex = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                groups[i].label,
                style: GoogleFonts.dmSans(
                  color: active ? AppColors.primary : AppColors.text3,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGrid(AlphabetGroup group) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.88,
      ),
      itemCount: group.entries.length,
      itemBuilder: (_, i) => _buildCard(group.entries[i]),
    );
  }

  Widget _buildCard(AlphabetEntry entry) {
    final speaking = _speakingChar == entry.char;
    final phonetic = entry.phoneticFor('latin');

    return GestureDetector(
      onTap: () => _speak(entry),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: speaking ? AppColors.primaryGlow : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: speaking ? AppColors.primary : AppColors.border,
            width: speaking ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              entry.char,
              style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w400,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              phonetic,
              style: GoogleFonts.dmSans(
                color: speaking ? AppColors.primary : AppColors.text3,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
