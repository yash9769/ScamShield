import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/premium_cta.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showError('Please fill all fields.');
      return;
    }
    if (!AuthService.isValidEmail(email)) {
      _showError('Please enter a valid email address.');
      return;
    }
    final passwordIssue = AuthService.validatePassword(password);
    if (passwordIssue != null) {
      _showError(passwordIssue);
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService.register(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result != AuthResult.success) {
      _showError(AuthService.messageFor(result));
      return;
    }

    await UserProfileService.updateProfile(name: name);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Account created successfully! Please sign in.', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.safeEmerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Security Profile', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Reveal(
                  delay: Reveal.step(0),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.safeEmerald.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.safeEmerald.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.verified_user_rounded, color: AppColors.safeEmerald, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Your account is stored locally on this device only. '
                                  'Password is hashed with PBKDF2-HMAC-SHA256 and never transmitted anywhere.',
                                  style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Reveal(
                          delay: Reveal.step(1),
                          child: TextField(
                            controller: _nameController,
                            style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.cobalt),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Reveal(
                          delay: Reveal.step(2),
                          child: TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(Icons.email_outlined, color: AppColors.cobalt),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Reveal(
                          delay: Reveal.step(3),
                          child: TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.cobalt),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppColors.mutedText),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Reveal(
                          delay: Reveal.step(4),
                          child: PremiumCTA(
                            label: "CREATE ENCRYPTED PROFILE",
                            onPressed: _isLoading ? null : _register,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
