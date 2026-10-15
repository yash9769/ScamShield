import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/google_sign_in_button.dart';
import '../main.dart';
import 'register_screen.dart';
import '../services/auth_service.dart';
import '../services/google_auth_service.dart';
import '../services/user_profile_service.dart';

/// The stock profile name UserProfileService starts from. Used to tell an
/// untouched profile apart from one the user has actually named.
const String _placeholderProfileName = 'Alex Chen';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.surfaceLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _goToApp() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainNavigation()),
    );
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter both email and password.');
      return;
    }
    if (!AuthService.isValidEmail(email)) {
      _showMessage('Please enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService.login(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result != AuthResult.success) {
      _showMessage(AuthService.messageFor(result));
      return;
    }
    _goToApp();
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    final result = await GoogleAuthService.signIn();
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() => _isGoogleLoading = false);
      // A user backing out of the Google sheet isn't an error worth shouting
      // about, so it gets no message at all.
      if (result.status != GoogleAuthStatus.cancelled) {
        _showMessage(result.message ?? 'Google sign-in failed.');
      }
      return;
    }

    final linked = await AuthService.completeGoogleSignIn(
      email: result.email!,
      displayName: result.displayName,
      photoUrl: result.photoUrl,
    );

    if (!linked) {
      // A different account is already registered on this device. Signing
      // in would otherwise hand this Google identity that account's scan
      // history and Safe Vault, and permanently destroy its password — so
      // refuse rather than silently taking it over. Also sign out of the
      // Google session itself: leaving it signed in would make the next tap
      // of this button silently reuse the same wrong account instead of
      // showing the picker again.
      await GoogleAuthService.signOut();
      if (!mounted) return;
      setState(() => _isGoogleLoading = false);
      _showMessage(
        'A different account is already set up on this device. Sign in with '
        'that account\'s own method, or delete it first from Settings > '
        'Privacy & Data.',
      );
      return;
    }

    // Adopt the Google display name only while the profile still holds the
    // stock placeholder — a user who renamed themselves in-app shouldn't have
    // that overwritten every time they sign in.
    final googleName = result.displayName;
    if (googleName != null &&
        googleName.isNotEmpty &&
        UserProfileService.nameNotifier.value == _placeholderProfileName) {
      await UserProfileService.updateProfile(name: googleName);
    }

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
    _goToApp();
  }

  void _continueAsGuest() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainNavigation()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isGoogleLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Reveal(delay: Reveal.step(0), child: _buildLogo()),
                  const SizedBox(height: 22),
                  Reveal(
                    delay: Reveal.step(1),
                    child: Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Reveal(
                    delay: Reveal.step(2),
                    child: const Text(
                      'Sign in to keep your scans, vault and\nbreach alerts in one place.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (GoogleAuthService.isConfigured) ...[
                    Reveal(
                      delay: Reveal.step(3),
                      child: GoogleSignInButton(
                        onPressed: busy ? null : _continueWithGoogle,
                        isLoading: _isGoogleLoading,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Reveal(delay: Reveal.step(4), child: const AuthDivider()),
                    const SizedBox(height: 20),
                  ],

                  Reveal(delay: Reveal.step(5), child: _buildForm(busy)),
                  const SizedBox(height: 18),

                  Reveal(
                    delay: Reveal.step(6),
                    child: TextButton(
                      onPressed: busy ? null : _continueAsGuest,
                      child: const Text(
                        'Continue without an account',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Reveal(
                    delay: Reveal.step(7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account?",
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                  ),
                          child: const Text(
                            'Create one',
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

  Widget _buildLogo() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
        ),
        child: ClipOval(
          child: Image.asset('assets/icon.png', width: 84, height: 84, fit: BoxFit.cover),
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
            controller: _emailController,
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
            autofillHints: const [AutofillHints.password],
            enabled: !busy,
            onSubmitted: (_) => _login(),
            style: const TextStyle(color: Colors.white, fontSize: 14.5),
            decoration: InputDecoration(
              labelText: 'Password',
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
              onPressed: busy ? null : _login,
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
                      'Sign in',
                      style: TextStyle(color: Colors.black, fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
