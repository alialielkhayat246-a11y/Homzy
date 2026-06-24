import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../i18n.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';

/// Shown once after the first login: pick Customer or Broker and add details.
class OnboardingRoleScreen extends StatefulWidget {
  const OnboardingRoleScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingRoleScreen> createState() => _OnboardingRoleScreenState();
}

class _OnboardingRoleScreenState extends State<OnboardingRoleScreen> {
  String? _role; // 'user' | 'broker'
  final _phone = TextEditingController();
  final _company = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_role == null) {
      setState(() => _error = tr('onb_choose_role'));
      return;
    }
    if (_phone.text.trim().isEmpty) {
      setState(() => _error = tr('onb_phone_required'));
      return;
    }
    if (_role == 'broker' && _company.text.trim().isEmpty) {
      setState(() => _error = tr('onb_company_required'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ProfileService.instance.saveRole(
        role: _role!,
        phone: _phone.text.trim(),
        company: _role == 'broker' ? _company.text.trim() : null,
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBroker = _role == 'broker';
    return Scaffold(
      backgroundColor: Brand.gray,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Center(child: HouseLogo(size: 56)),
              const SizedBox(height: 16),
              Text(tr('onb_title'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(tr('onb_sub'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.muted)),
              const SizedBox(height: 24),
              Text(tr('onb_i_am'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _roleCard(
                value: 'user',
                icon: Icons.person_search_outlined,
                title: tr('onb_user_title'),
                desc: tr('onb_user_desc'),
              ),
              const SizedBox(height: 10),
              _roleCard(
                value: 'broker',
                icon: Icons.badge_outlined,
                title: tr('onb_broker_title'),
                desc: tr('onb_broker_desc'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: _dec(tr('onb_phone'), Icons.phone_outlined),
              ),
              if (isBroker) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _company,
                  decoration:
                      _dec(tr('onb_company'), Icons.business_outlined),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Brand.red, fontSize: 13)),
              ],
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(tr('onb_continue')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.line),
        ),
      );

  Widget _roleCard({
    required String value,
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final selected = _role == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _role = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Brand.blueLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Brand.blue : Brand.line,
              width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: Brand.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(desc,
                      style:
                          const TextStyle(color: Brand.muted, fontSize: 12)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: Brand.blue),
          ],
        ),
      ),
    );
  }
}
