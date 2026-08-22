import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'main.dart'; // for AccaColors

class ChooseUsernameScreen extends StatefulWidget {
  final String? suggestedDisplayName;
  const ChooseUsernameScreen({super.key, this.suggestedDisplayName});

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final usernameController = TextEditingController();
  late final displayNameController = TextEditingController(text: widget.suggestedDisplayName ?? '');

  bool isSubmitting = false;
  String? errorMessage;

  Future<void> submit() async {
    if (usernameController.text.trim().isEmpty || displayNameController.text.trim().isEmpty) {
      setState(() => errorMessage = 'Both fields are required.');
      return;
    }
    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });
    try {
      final user = await AuthService.instance.completeOAuthSignUp(
        username: usernameController.text.trim(),
        displayName: displayNameController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(user);
    } catch (e) {
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString().replaceFirst('AuthException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccaColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "You're almost in",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick a username and confirm your display name to finish setting up your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 24),
              const Text('Username', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 4),
              TextField(
                controller: usernameController,
                textCapitalization: TextCapitalization.none,
                style: const TextStyle(color: Colors.black, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Display name', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 4),
              TextField(
                controller: displayNameController,
                style: const TextStyle(color: Colors.black, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
                  ),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isSubmitting ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccaColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}