import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/agency_service.dart';
import '../theme.dart';

String _tx(String en, String ar) => Lang.instance.isAr ? ar : en;

class AgencyTeamScreen extends StatefulWidget {
  const AgencyTeamScreen({super.key});
  @override
  State<AgencyTeamScreen> createState() => _AgencyTeamScreenState();
}

class _AgencyTeamScreenState extends State<AgencyTeamScreen> {
  AgencyWorkspace? workspace;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await AgencyService.instance.workspace();
      if (mounted) {
        setState(() {
          workspace = value;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = workspace;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tx('Agency team', 'فريق الوكالة')),
        actions: [
          if (ws?.can('team.manage') == true)
            IconButton(
              onPressed: addMember,
              tooltip: _tx('Add member', 'إضافة عضو'),
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          if (ws?.can('team.manage') == true)
            IconButton(
              onPressed: createTeam,
              tooltip: _tx('Create team', 'إنشاء فريق'),
              icon: const Icon(Icons.group_add_outlined),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: FilledButton(
                      onPressed: load,
                      child: Text(_tx('Retry', 'إعادة المحاولة'))))
              : ws == null
                  ? Center(
                      child: Text(
                          _tx('Create an agency first.', 'أنشئ وكالة أولًا.')))
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            color: Brand.navy,
                            child: ListTile(
                              leading: const CircleAvatar(
                                  child: Icon(Icons.business)),
                              title: Text('${ws.agency['name']}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                _tx('${ws.roster.length} members · ${ws.teams.length} teams',
                                    '${ws.roster.length} أعضاء · ${ws.teams.length} فرق'),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(_tx('Members', 'الأعضاء'),
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          ...ws.roster.map((member) => memberCard(ws, member)),
                          const SizedBox(height: 16),
                          Text(_tx('Teams', 'الفرق'),
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          if (ws.teams.isEmpty)
                            Text(_tx('No teams yet.', 'لا توجد فرق بعد.'),
                                style: const TextStyle(color: Brand.muted)),
                          ...ws.teams.map((team) => Card(
                                child: ListTile(
                                  leading: const Icon(Icons.groups_outlined),
                                  title: Text('${team['name'] ?? ''}'),
                                ),
                              )),
                        ],
                      ),
                    ),
    );
  }

  Widget memberCard(AgencyWorkspace ws, Map<String, dynamic> member) {
    final isOwner = member['is_owner'] == true;
    final status = '${member['status'] ?? 'active'}';
    final displayRole =
        Lang.instance.isAr ? member['role_ar'] : member['role_en'];
    final roles = ws.roles.where((role) => role['key'] != 'owner').toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text('${member['name'] ?? member['phone'] ?? ''}'),
            subtitle: Text('${displayRole ?? member['role_key'] ?? ''}'),
            trailing: Chip(
                label: Text(status == 'active'
                    ? _tx('Active', 'نشط')
                    : _tx('Suspended', 'موقوف'))),
          ),
          if (ws.can('team.manage') && !isOwner)
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue:
                      roles.any((role) => role['key'] == member['role_key'])
                          ? member['role_key']?.toString()
                          : null,
                  decoration: InputDecoration(labelText: _tx('Role', 'الدور')),
                  items: roles.map((role) {
                    final name =
                        Lang.instance.isAr ? role['name_ar'] : role['name_en'];
                    return DropdownMenuItem(
                        value: '${role['key']}',
                        child: Text('${name ?? role['key']}'));
                  }).toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    await AgencyService.instance.setMemberRole(
                        '${ws.agency['id']}', '${member['user_id']}', value);
                    await load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: status == 'active'
                    ? _tx('Suspend', 'إيقاف')
                    : _tx('Activate', 'تفعيل'),
                icon: Icon(status == 'active'
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline),
                onPressed: () async {
                  await AgencyService.instance.setMemberStatus(
                      '${ws.agency['id']}',
                      '${member['user_id']}',
                      status == 'active' ? 'suspended' : 'active');
                  await load();
                },
              ),
            ]),
        ]),
      ),
    );
  }

  Future<void> addMember() async {
    final ws = workspace!;
    final query = TextEditingController();
    Map<String, dynamic>? found;
    String? errorText;
    var searching = false;
    var saving = false;
    var role = 'agent';
    String? team;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_tx('Add agency member', 'إضافة عضو للوكالة')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: query,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText:
                      _tx('Homzy phone or email', 'هاتف أو بريد حساب Homzy'),
                  errorText: errorText,
                  suffixIcon: IconButton(
                    icon: searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    onPressed: searching
                        ? null
                        : () async {
                            if (query.text.trim().length < 3) return;
                            setDialogState(() {
                              searching = true;
                              errorText = null;
                            });
                            try {
                              final value = await AgencyService.instance
                                  .lookupUser(
                                      '${ws.agency['id']}', query.text.trim());
                              setDialogState(() {
                                found = value;
                                searching = false;
                                if (value == null) {
                                  errorText = _tx('No Homzy user found',
                                      'لم يتم العثور على مستخدم Homzy');
                                }
                              });
                            } catch (e) {
                              setDialogState(() {
                                searching = false;
                                errorText = '$e';
                              });
                            }
                          },
                  ),
                ),
              ),
              if (found != null) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(
                      '${found!['name'] ?? found!['phone'] ?? found!['email'] ?? ''}'),
                  subtitle: Text('${found!['phone'] ?? found!['email'] ?? ''}'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: _tx('Role', 'الدور')),
                  items: ws.roles
                      .where((item) => item['key'] != 'owner')
                      .map((item) {
                    final name =
                        Lang.instance.isAr ? item['name_ar'] : item['name_en'];
                    return DropdownMenuItem(
                        value: '${item['key']}',
                        child: Text('${name ?? item['key']}'));
                  }).toList(),
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? 'agent'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: team,
                  decoration: InputDecoration(
                      labelText: _tx('Team (optional)', 'الفريق (اختياري)')),
                  items: ws.teams
                      .map((item) => DropdownMenuItem(
                            value: '${item['id']}',
                            child: Text('${item['name']}'),
                          ))
                      .toList(),
                  onChanged: (value) => setDialogState(() => team = value),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('cancel'))),
            FilledButton(
              onPressed: found == null || saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await AgencyService.instance.addMember(
                            '${ws.agency['id']}',
                            '${found!['id']}',
                            role,
                            team);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await load();
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          errorText = '$e';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_tx('Add', 'إضافة')),
            ),
          ],
        ),
      ),
    );
    query.dispose();
  }

  Future<void> createTeam() async {
    final ws = workspace!;
    final controller = TextEditingController();
    String? leader;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(_tx('Create team', 'إنشاء فريق')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: controller,
                decoration:
                    InputDecoration(labelText: _tx('Team name', 'اسم الفريق'))),
            DropdownButtonFormField<String>(
              initialValue: leader,
              decoration:
                  InputDecoration(labelText: _tx('Team leader', 'قائد الفريق')),
              items: ws.roster
                  .where((m) => m['status'] == 'active')
                  .map((member) => DropdownMenuItem(
                      value: '${member['user_id']}',
                      child:
                          Text('${member['name'] ?? member['phone'] ?? ''}')))
                  .toList(),
              onChanged: (value) => update(() => leader = value),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('cancel'))),
            FilledButton(
                onPressed: () async {
                  if (controller.text.trim().length < 2) return;
                  await AgencyService.instance.createTeam(
                      '${ws.agency['id']}', controller.text.trim(), leader);
                  if (context.mounted) Navigator.pop(context);
                  await load();
                },
                child: Text(tr('save'))),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}
