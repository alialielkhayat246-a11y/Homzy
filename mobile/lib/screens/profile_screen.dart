import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';
import '../widgets/lang_toggle.dart';
import 'saved_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  String? _avatarUrl;
  String? _role;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await ProfileService.instance.get();
    if (!mounted) return;
    setState(() {
      _name.text = (p?['full_name'] ?? AuthService.instance.displayName ?? '')
          .toString();
      _phone.text = (p?['phone'] ?? '').toString();
      _company.text = (p?['company'] ?? '').toString();
      _avatarUrl = p?['avatar_url'] as String?;
      _role = p?['role'] as String?;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ProfileService.instance.update(
        fullName: _name.text.trim(),
        phone: _phone.text.trim(),
        company: _role == 'broker' ? _company.text.trim() : null,
      );
      _toast(tr('saved_done'));
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (x == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await x.readAsBytes();
      final ext = x.name.split('.').last.toLowerCase();
      final url = await ProfileService.instance
          .uploadAvatar(bytes, ext == 'png' ? 'png' : 'jpeg');
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('delete_account')),
        content: Text(tr('delete_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Brand.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('delete_account')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ProfileService.instance.deleteAccount();
      // AuthGate reacts to sign-out and returns to the login screen.
    } catch (e) {
      _toast('$e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('my_account')),
        actions: const [
          Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: LangToggle())),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Stack(
                    children: [
                      _Avatar(url: _avatarUrl, uploading: _uploading),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: Brand.blue,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploading ? null : _pickAvatar,
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(Icons.camera_alt,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(AuthService.instance.email ?? '',
                      style: const TextStyle(color: Brand.muted, fontSize: 13)),
                ),
                const SizedBox(height: 24),
                _field(_name, tr('full_name'), Icons.person_outline),
                const SizedBox(height: 12),
                _field(_phone, tr('onb_phone'), Icons.phone_outlined,
                    keyboard: TextInputType.phone),
                if (_role == 'broker') ...[
                  const SizedBox(height: 12),
                  _field(_company, tr('onb_company'), Icons.business_outlined),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(tr('save')),
                  ),
                ),
                const SizedBox(height: 24),
                _tile(Icons.bookmark_border, tr('open_saved_chats'), () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SavedScreen()));
                }),
                _tile(Icons.logout, tr('sign_out'),
                    () => AuthService.instance.signOut()),
                _tile(Icons.delete_outline, tr('delete_account'),
                    _deleteAccount,
                    danger: true),
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.line),
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? Brand.red : Brand.navy;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.line),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color)),
        trailing: Icon(Icons.chevron_right, color: color.withValues(alpha: .5)),
        onTap: onTap,
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url, required this.uploading});
  final String? url;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: const BoxDecoration(
          color: Brand.navy, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: uploading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : (url != null
              ? Image.network(url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                      child: BrokerAvatar(size: 60)))
              : const Center(child: BrokerAvatar(size: 60))),
    );
  }
}
