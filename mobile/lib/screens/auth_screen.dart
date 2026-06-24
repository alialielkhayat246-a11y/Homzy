import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';
import '../widgets/lang_toggle.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_isSignUp) {
        final res = await AuthService.instance.signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
        );
        // If email confirmation is on, there's no session yet.
        if (res.session == null && mounted) {
          setState(() => _info =
              'Account created! Check your email to confirm, then log in.');
          setState(() => _isSignUp = false);
        }
      } else {
        await AuthService.instance.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // On success the AuthGate stream navigates away automatically.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      // Returns immediately after launching the browser; the AuthGate stream
      // navigates once the deep-link callback completes the sign-in.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Google sign-in unavailable. Try email for now.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.gray,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                      alignment: Alignment.centerRight, child: LangToggle()),
                  const SizedBox(height: 8),
                  const HouseLogo(size: 64),
                  const SizedBox(height: 12),
                  Text('Homzy',
                      style: GoogleFonts.poppins(
                          fontSize: 26, fontWeight: FontWeight.w700)),
                  Text(
                    _isSignUp ? tr('create_account') : tr('welcome_back'),
                    style: const TextStyle(color: Brand.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Brand.line),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_isSignUp) ...[
                            _field(_name, tr('full_name'),
                                icon: Icons.person_outline),
                            const SizedBox(height: 12),
                          ],
                          _field(_email, tr('email'),
                              icon: Icons.mail_outline,
                              keyboard: TextInputType.emailAddress,
                              validator: (v) =>
                                  (v == null || !v.contains('@'))
                                      ? tr('enter_valid_email')
                                      : null),
                          const SizedBox(height: 12),
                          _field(_password, tr('password'),
                              icon: Icons.lock_outline,
                              obscure: true,
                              validator: (v) => (v == null || v.length < 6)
                                  ? tr('password_min')
                                  : null),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: const TextStyle(
                                    color: Brand.red, fontSize: 13)),
                          ],
                          if (_info != null) ...[
                            const SizedBox(height: 12),
                            Text(_info!,
                                style: const TextStyle(
                                    color: Brand.green, fontSize: 13)),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : Text(_isSignUp
                                      ? tr('sign_up')
                                      : tr('sign_in')),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _google,
                            icon: const Icon(Icons.g_mobiledata, size: 26),
                            label: Text(tr('continue_google')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              side: const BorderSide(color: Brand.line),
                              foregroundColor: Brand.navy,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                              _info = null;
                            }),
                    child: Text(
                      _isSignUp ? tr('have_account') : tr('new_here'),
                      style: const TextStyle(color: Brand.blue),
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

  Widget _field(
    TextEditingController c,
    String label, {
    IconData? icon,
    bool obscure = false,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        filled: true,
        fillColor: Brand.gray,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
