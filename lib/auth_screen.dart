import 'package:flutter/material.dart';
import 'app_state.dart';
import 'auth_service.dart';
import 'main.dart'; // for AccaColors

enum AuthMode { login, createAccount }

class AuthScreen extends StatefulWidget {
  final AppState appState;
  final VoidCallback onAuthenticated;

  const AuthScreen({super.key, required this.appState, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode mode = AuthMode.login;

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final emailController = TextEditingController();
  final displayNameController = TextEditingController();

  bool rememberMe = true;
  bool isLoading = false;
  String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccaColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Acca Central',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AccaColors.primary),
              ),
              const SizedBox(height: 24),
              SegmentedButton<AuthMode>(
                segments: const [
                  ButtonSegment(value: AuthMode.login, label: Text('Log in')),
                  ButtonSegment(value: AuthMode.createAccount, label: Text('Create account')),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => setState(() => mode = selection.first),
              ),
              const SizedBox(height: 24),
              _field('Username', usernameController),
              if (mode == AuthMode.createAccount) ...[
                const SizedBox(height: 14),
                _field('Display name', displayNameController),
                const SizedBox(height: 14),
                _field('Email', emailController, keyboardType: TextInputType.emailAddress),
              ],
              const SizedBox(height: 14),
              _field('Password', passwordController, obscure: true),
              if (mode == AuthMode.createAccount) ...[
                const SizedBox(height: 14),
                _field('Confirm password', confirmPasswordController, obscure: true),
              ],
              if (mode == AuthMode.login) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: rememberMe,
                      activeColor: AccaColors.gold,
                      onChanged: (v) => setState(() => rememberMe = v ?? true),
                    ),
                    const Text('Remember me'),
                  ],
                ),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccaColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(mode == AuthMode.login ? 'Log in' : 'Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {bool obscure = false, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> submit() async {
    setState(() {
      errorMessage = null;
      isLoading = true;
    });

    try {
      if (mode == AuthMode.login) {
        final user = await AuthService.instance.logIn(
          username: usernameController.text.trim(),
          password: passwordController.text,
        );
        await widget.appState.setRememberMe(rememberMe);
        widget.appState.didLogIn(user);
      } else {
        if (passwordController.text != confirmPasswordController.text) {
          throw AuthException("Passwords don't match.");
        }
        final user = await AuthService.instance.signUp(
          username: usernameController.text.trim(),
          email: emailController.text.trim(),
          password: passwordController.text,
          displayName: displayNameController.text.trim(),
        );
        await widget.appState.setRememberMe(true);
        widget.appState.didLogIn(user);
      }
      widget.onAuthenticated();
    } catch (e) {
      setState(() => errorMessage = e.toString().replaceFirst('AuthException: ', ''));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
}