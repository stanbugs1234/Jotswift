import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/skins/notely_skin.dart';
import '../../core/skins/skin_manifest.dart';
import '../../core/skins/widgets/paper.dart';
import '../../shared/ui/legal_links.dart';
import 'auth_repository.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creatingAccount = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AuthRepository auth) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(authRepositoryProvider));
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitEmail() => _run(
    (auth) => _creatingAccount
        ? auth.createAccountWithEmail(_email.text, _password.text)
        : auth.signInWithEmail(_email.text, _password.text),
  );

  @override
  Widget build(BuildContext context) {
    final skin = NotelySkin.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Paper(
                pattern: PaperPattern.blank,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Jotswift',
                      textAlign: TextAlign.center,
                      style: skin.accentTextStyle.copyWith(fontSize: 44),
                    ),
                    Text(
                      'Notes, planner, calendar and to-dos',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run((a) => a.signInWithApple()),
                      icon: const Icon(Icons.apple),
                      label: const Text('Continue with Apple'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run((a) => a.signInWithGoogle()),
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('or'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _submitEmail(),
                    ),
                    if (_error case final error?) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submitEmail,
                      child: Text(
                        _creatingAccount ? 'Create account' : 'Sign in',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _creatingAccount = !_creatingAccount,
                            ),
                      child: Text(
                        _creatingAccount
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'By continuing you agree to the Terms of Use and '
                      'Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const LegalFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
