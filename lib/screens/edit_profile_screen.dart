import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_storage.dart';
import '../utils/avatar_data.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  final _searchCtrl = TextEditingController();
  int? _avatarIndex;
  String _avatarSearch = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: AppStorage.instance.userName);
    _avatarIndex = AppStorage.instance.selectedAvatar;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AppStorage.instance
        .saveProfile(_nameCtrl.text.trim(), AppStorage.instance.userHobby);
    if (_avatarIndex != null) {
      await AppStorage.instance.saveAvatar(_avatarIndex!);
    }
    if (mounted) Navigator.pop(context);
  }

  void _confirmDelete() {
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
              'Delete profile?',
              style: GoogleFonts.cormorantGaramond(
                  color: AppColors.text, fontSize: 26, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              "This permanently deletes your account and all local progress. This can't be undone.",
              style: GoogleFonts.dmSans(
                  color: AppColors.text2, fontSize: 14, height: 1.5),
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
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
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
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Delete',
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final q = _avatarSearch.toLowerCase();
    final indices = q.isEmpty
        ? List.generate(allAvatars.length, (i) => i)
        : [
            for (int i = 0; i < allAvatars.length; i++)
              if (allAvatars[i].name.toLowerCase().contains(q) ||
                  allAvatars[i].country.toLowerCase().contains(q))
                i,
          ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Edit profile',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w500)),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('Save',
                style: GoogleFonts.dmSans(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
                decoration: const InputDecoration(hintText: 'Your name'),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('AVATAR',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _avatarSearch = v),
                style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search city or country…',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _avatarSearch.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _avatarSearch = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 92,
                ),
                itemCount: indices.length,
                itemBuilder: (_, fi) {
                  final i = indices[fi];
                  final city = allAvatars[i];
                  final isSelected = _avatarIndex == i;
                  return GestureDetector(
                    onTap: () => setState(() => _avatarIndex = i),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 3),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.4),
                                        blurRadius: 14),
                                  ]
                                : null,
                          ),
                          child: ClipOval(child: _buildAvatarCircle(city, 56)),
                        ),
                        const SizedBox(height: 4),
                        Text(city.name,
                            style: GoogleFonts.dmSans(
                                color: isSelected
                                    ? AppColors.primarySoft
                                    : AppColors.text2,
                                fontSize: 9,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _confirmDelete,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Delete profile',
                      style: GoogleFonts.dmSans(
                          color: const Color(0xFFFF6B6B),
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
