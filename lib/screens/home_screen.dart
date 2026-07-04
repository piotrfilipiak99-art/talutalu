import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_storage.dart';
import '../widgets/alphabet_panel.dart';
import 'read_screen.dart';
import 'flashcards_screen.dart';
import 'converse_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('talutalu/app');
  int _selectedIndex = 0;

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.menu_book_rounded, label: 'Read'),
    _NavItem(icon: Icons.style_rounded, label: 'Flashcards'),
    _NavItem(icon: Icons.forum_rounded, label: 'Converse'),
    _NavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    // AppColors reads a mutable global flag, not Theme.of(context) — most
    // screens' widgets are cheap to rebuild but not automatically notified,
    // so force a full remount of the tab content on every flip via the key
    // below rather than hunting down every const widget that would
    // otherwise keep showing stale colors.
    AppStorage.instance.darkMode.addListener(_onThemeChanged);
    // Read hands a selected sentence off to Converse through this notifier
    // — the tab switch happens here, the conversation itself is opened by
    // ConverseScreen's own listener (alive inside the IndexedStack).
    AppStorage.instance.explainRequest.addListener(_onExplainRequested);
  }

  @override
  void dispose() {
    AppStorage.instance.darkMode.removeListener(_onThemeChanged);
    AppStorage.instance.explainRequest.removeListener(_onExplainRequested);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onExplainRequested() {
    if (AppStorage.instance.explainRequest.value == null || !mounted) return;
    setState(() => _selectedIndex = 2); // Converse tab
  }

  void _onTabTap(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // No native channel on web — the browser handles back navigation.
        if (!didPop && !kIsWeb) _channel.invokeMethod('moveToBackground');
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: KeyedSubtree(
          key: ValueKey(AppStorage.instance.darkMode.value),
          child: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    ReadScreen(),
                    FlashcardsScreen(),
                    ConverseScreen(),
                    ProfileScreen(),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable:
                    AppStorage.instance.hideAlphabetPanel,
                builder: (_, hide, __) =>
                    hide ? const SizedBox.shrink() : AlphabetPanel(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildNavBar(),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              final active = _selectedIndex == i;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onTabTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: active ? AppColors.primaryGlow : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.icon,
                          size: 22,
                          color: active ? AppColors.primary : AppColors.text3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: GoogleFonts.dmSans(
                          color: active ? AppColors.primary : AppColors.text3,
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
