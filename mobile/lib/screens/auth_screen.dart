import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _phone.dispose();
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
          phone: _phone.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
        );
        // If email confirmation is on, there's no session yet.
        if (res.session == null && mounted) {
          setState(() => _info = tr('account_created_sign_in'));
          setState(() => _isSignUp = false);
        }
      } else {
        await AuthService.instance.signIn(
          phone: _phone.text.trim(),
          password: _password.text,
        );
      }
      // On success the AuthGate stream navigates away automatically.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _authMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = tr('auth_generic_error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Supabase errors come back in English; show the common ones in the app's language.
  String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return tr('auth_wrong_login');
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return tr('auth_already_registered');
    }
    return Lang.instance.isAr ? tr('auth_generic_error') : e.message;
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
        setState(() => _error = tr('google_unavailable_phone'));
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
                                key: const ValueKey('name'),
                                icon: Icons.person_outline,
                                validator: (v) =>
                                    (v == null || v.trim().length < 2)
                                        ? tr('name_required')
                                        : null),
                            const SizedBox(height: 12),
                          ],
                          _field(_phone, tr('phone_number'),
                              key: const ValueKey('phone'),
                              icon: Icons.phone_outlined,
                              keyboard: TextInputType.phone,
                              formatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+]')),
                                LengthLimitingTextInputFormatter(14),
                              ],
                              validator: (v) => v == null ||
                                      !AuthService.isValidEgyptianPhone(v)
                                  ? tr('enter_valid_phone')
                                  : null),
                          const SizedBox(height: 12),
                          _field(_password, tr('password'),
                              key: const ValueKey('password'),
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
                                          strokeWidth: 2, color: Colors.white))
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
                        : () {
                            // drop the other mode's validation messages but keep what was typed
                            final phone = _phone.text, name = _name.text;
                            _formKey.currentState?.reset();
                            _phone.text = phone;
                            _name.text = name;
                            setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                              _info = null;
                            });
                          },
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
    Key? key,
    IconData? icon,
    bool obscure = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      inputFormatters: formatters,
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
