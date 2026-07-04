import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/app_storage.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _repeatPasswordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureRepeat = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _repeatPasswordCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.dmSans()),
      backgroundColor: AppColors.card,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    final isCreatingAccount = _tabCtrl.index == 1;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      _showError('Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      _showError('Password must be at least 8 characters.');
      return;
    }
    if (isCreatingAccount && password != _repeatPasswordCtrl.text) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (isCreatingAccount) {
        await ApiClient.instance.register(email, password);
      } else {
        await ApiClient.instance.login(email, password);
        await AppStorage.instance.setLoggedIn(true);
        // Bring this account's data down before showing Home; if it fails
        // (offline), local data still works and syncs later.
        try {
          await AppStorage.instance.syncNow();
        } on ApiException {
          // ignore: sync retries on next write / app start
        }
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        isCreatingAccount ? '/onboarding' : '/home',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'talutalu',
                    style: GoogleFonts.cormorantGaramond(
                      color: AppColors.text,
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -1,
                    ),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 6, left: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              _buildTabBar(),
              const SizedBox(height: 36),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _tabCtrl.index == 0
                    ? _buildSignInForm(key: const ValueKey('signin'))
                    : _buildRegisterForm(key: const ValueKey('register')),
              ),
              const SizedBox(height: 28),
              _buildSubmitButton(),
              const SizedBox(height: 24),
              _buildDivider(),
              const SizedBox(height: 24),
              _buildGoogleButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TabBar(
        controller: _tabCtrl,
        indicator: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.border),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelColor: AppColors.text,
        unselectedLabelColor: AppColors.text2,
        padding: const EdgeInsets.all(4),
        tabs: const [
          Tab(text: 'Sign in'),
          Tab(text: 'Create account'),
        ],
      ),
    );
  }

  Widget _buildSignInForm({Key? key}) {
    return Column(
      key: key,
      children: [
        _buildField(
          controller: _emailCtrl,
          hint: 'Email address',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _buildPasswordField(),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {},
            child: Text(
              'Forgot password?',
              style: GoogleFonts.dmSans(
                color: AppColors.primarySoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm({Key? key}) {
    return Column(
      key: key,
      children: [
        _buildField(
          controller: _emailCtrl,
          hint: 'Email address',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _buildPasswordField(),
        const SizedBox(height: 14),
        _buildRepeatPasswordField(),
        const SizedBox(height: 12),
        Text(
          'By creating an account you agree to our Terms of Service and Privacy Policy.',
          style: GoogleFonts.dmSans(
            color: AppColors.text3,
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildRepeatPasswordField() {
    return TextField(
      controller: _repeatPasswordCtrl,
      obscureText: _obscureRepeat,
      style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Repeat password',
        prefixIcon: Icon(Icons.lock_outline_rounded, color: AppColors.text3, size: 20),
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _obscureRepeat = !_obscureRepeat),
          child: Icon(
            _obscureRepeat ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.text3,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.text3, size: 20),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Password',
        prefixIcon: Icon(Icons.lock_outline_rounded, color: AppColors.text3, size: 20),
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          child: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.text3,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _submit,
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
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                _tabCtrl.index == 0 ? 'Sign in' : 'Create account',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: GoogleFonts.dmSans(color: AppColors.text3, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'G',
              style: GoogleFonts.dmSans(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Continue with Google',
              style: GoogleFonts.dmSans(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
