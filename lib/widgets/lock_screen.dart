import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../services/biometric_service.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometricUnlock();
    });
  }

  Future<void> _tryBiometricUnlock() async {
    final app = Provider.of<AppState>(context, listen: false);
    if (app.biometricEnabled) {
      final isAvailable = await BiometricService.isBiometricsAvailable();
      if (isAvailable) {
        final success = await BiometricService.authenticate();
        if (success && mounted) {
          final unlocked = await app.verifyBiometricsAndUnlock();
          if (!unlocked && mounted) {
            setState(() {
              _error = 'Biometric verification failed. Please enter your password.';
            });
          }
        }
      }
    }
  }

  Future<void> _unlockWithPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final app = Provider.of<AppState>(context, listen: false);
    final success = await app.verifyMasterPassword(password);

    if (mounted) {
      setState(() {
        _loading = false;
        if (!success) {
          _error = 'Incorrect master password. Please try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 80,
                  color: scheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Noteflow Locked',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please enter your master password to unlock your notes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    hintText: 'Enter password…',
                    errorText: _error,
                    suffixIcon: app.biometricEnabled
                        ? IconButton(
                            icon: const Icon(Icons.fingerprint),
                            tooltip: 'Unlock with Biometrics',
                            onPressed: _tryBiometricUnlock,
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _unlockWithPassword(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _unlockWithPassword,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Unlock'),
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
