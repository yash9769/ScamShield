import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/google_sign_in_button.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/google_auth_service.dart';
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
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage('Please fill all fields.');
      return;
    }
    if (!AuthService.isValidEmail(email)) {
      _showMessage('Please enter a valid email address.');
      return;
    }
    final passwordIssue = AuthService.validatePassword(password);
    if (passwordIssue != null) {
      _showMessage(passwordIssue);
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService.register(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result != AuthResult.success) {
      _showMessage(AuthService.messageFor(result));
      return;
    }

    await UserProfileService.updateProfile(name: name);
    if (!mounted) return;

    _showMessage('Account created. Please sign in.', isError: false);
    Navigator.pop(context);
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    final result = await GoogleAuthService.signIn();
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() => _isGoogleLoading = false);
      if (result.status != GoogleAuthStatus.cancelled) {
        _showMessage(result.message ?? 'Google sign-up failed.');
      }
      return;
    }

    await AuthService.completeGoogleSignIn(
      email: result.email!,
      displayName: result.displayName,
      photoUrl: result.photoUrl,
    );
    // Seed the in-app profile with the Google display name so the user isn't
    // asked for a name they've already effectively given us.
    if (result.displayName != null && result.displayName!.isNotEmpty) {
      await UserProfileService.updateProfile(name: result.displayName!);
    }
    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    // Google sign-up leaves the session active, so go straight into the app
    // rather than bouncing back to a sign-in screen the user can't use.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainNavigation()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isGoogleLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Reveal(
                    delay: Reveal.step(0),
                    child: Text(
                      'Set up your shield',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Reveal(
                    delay: Reveal.step(1),
                    child: const Text(
                      'Your account, scan history and Safe Vault stay on this '
                      'device — nothing is uploaded to a ScamShield server.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 26),

                  if (GoogleAuthService.isConfigured) ...[
                    Reveal(
                      delay: Reveal.step(2),
                      child: GoogleSignInButton(
                        onPressed: busy ? null : _continueWithGoogle,
                        isLoading: _isGoogleLoading,
                        label: 'Sign up with Google',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Reveal(delay: Reveal.step(3), child: const AuthDivider()),
                    const SizedBox(height: 20),
                  ],

                  Reveal(delay: Reveal.step(4), child: _buildForm(busy)),
                  const SizedBox(height: 18),

                  Reveal(
                    delay: Reveal.step(5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account?',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => Navigator.pop(context),
                          child: const Text(
                            'Sign in',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool busy) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            enabled: !busy,
            onSubmitted: (_) => _emailFocus.requestFocus(),
            style: const TextStyle(color: Colors.white, fontSize: 14.5),
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline, color: AppColors.primary, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            enabled: !busy,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            style: const TextStyle(color: Colors.white, fontSize: 14.5),
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email, color: AppColors.primary, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !busy,
            onSubmitted: (_) => _register(),
            style: const TextStyle(color: Colors.white, fontSize: 14.5),
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'At least 8 characters, with letters and numbers.',
              helperStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: busy ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black),
                    )
                  : const Text(
                      'Create account',
                      style: TextStyle(color: Colors.black, fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
