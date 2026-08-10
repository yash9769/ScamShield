import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/motion.dart';
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
      SnackBar(content: Text(message), backgroundColor: AppColors.danger, behavior: SnackBarBehavior.floating),
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
      const SnackBar(content: Text('Account created successfully! Please sign in.'), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Security Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                    border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    children: [
                      Reveal(
                        delay: Reveal.step(1),
                        child: TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline, color: AppColors.primary),
                        ),
                      ),
                      ),
                      const SizedBox(height: 16),
                      Reveal(
                        delay: Reveal.step(2),
                        child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: Icon(Icons.email_outlined, color: AppColors.primary),
                        ),
                      ),
                      ),
                      const SizedBox(height: 16),
                      Reveal(
                        delay: Reveal.step(3),
                        child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textSecondary),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      ),
                      const SizedBox(height: 24),
                      Reveal(
                        delay: Reveal.step(4),
                        child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                              : const Text('CREATE ENCRYPTED PROFILE', style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ),
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
