import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../services/agency_service.dart';
import '../theme.dart';

const ownerStages = [
  'new',
  'not_contacted',
  'contacted',
  'interested',
  'info_collected',
  'verification',
  'owner_approval',
  'ready_marketing',
  'active_listing',
];

String _label(String en, String ar) => Lang.instance.isAr ? ar : en;

String _stageLabel(String stage) {
  const labels = {
    'new': ['New', 'جديد'],
    'not_contacted': ['Not contacted', 'لم يتم التواصل'],
    'contacted': ['Contacted', 'تم التواصل'],
    'interested': ['Interested', 'مهتم'],
    'info_collected': ['Info collected', 'تم جمع البيانات'],
    'verification': ['Verification', 'مراجعة'],
    'owner_approval': ['Owner approval', 'موافقة المالك'],
    'ready_marketing': ['Ready for marketing', 'جاهز للتسويق'],
    'active_listing': ['Active listing', 'إعلان نشط'],
  };
  final value = labels[stage] ?? const ['New', 'جديد'];
  return _label(value[0], value[1]);
}

class AgencyOwnersScreen extends StatefulWidget {
  const AgencyOwnersScreen({super.key});

  @override
  State<AgencyOwnersScreen> createState() => _AgencyOwnersScreenState();
}

class _AgencyOwnersScreenState extends State<AgencyOwnersScreen> {
  AgencyWorkspace? _workspace;
  List<Map<String, dynamic>> _owners = const [];
  bool _loading = true;
  String? _error;
  String _stage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workspace = await AgencyService.instance.workspace();
      final owners = workspace == null
          ? <Map<String, dynamic>>[]
          : await AgencyService.instance.owners('${workspace.agency['id']}');
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _owners = owners;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
          title: Text(_label('Owners & acquisition', 'المُلّاك والتوريد'))),
      floatingActionButton: workspace?.can('owner.create') == true
          ? FloatingActionButton.extended(
              onPressed: _addOwner,
              icon: const Icon(Icons.add),
              label: Text(_label('Add owner', 'إضافة مالك')),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, retry: _load)
              : workspace == null
                  ? _CreateAgency(onCreated: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        children: [
                          Text('${workspace.agency['name']}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 42,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _stageChip('', _label('All', 'الكل')),
                                for (final stage in ownerStages)
                                  _stageChip(stage, _stageLabel(stage)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._owners
                              .where((row) =>
                                  _stage.isEmpty || row['stage'] == _stage)
                              .map((row) => _ownerCard(workspace, row)),
                          if (_owners.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(36),
                              child: Center(
                                  child: Text(_label('No owners yet.',
                                      'لا يوجد مُلّاك بعد.'))),
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _stageChip(String value, String text) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          label: Text(text),
          selected: _stage == value,
          onSelected: (_) => setState(() => _stage = value),
        ),
      );

  Widget _ownerCard(AgencyWorkspace workspace, Map<String, dynamic> owner) {
    final phone = owner['phone']?.toString() ?? '';
    final stage = owner['stage']?.toString() ?? 'new';
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final canAssignTeam = workspace.can('team.manage');
    final roster = workspace.roster
        .where((member) =>
            member['status'] == 'active' &&
            (canAssignTeam || member['user_id'] == currentUserId))
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${owner['name'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Chip(
              label: Text(owner['source_kind'] == 'company'
                  ? _label('Company', 'شركة')
                  : _label('Agent', 'موظف')),
            ),
          ]),
          Text(
              [owner['property_ref'], owner['property_type'], owner['area']]
                  .where((value) => value != null && '$value'.isNotEmpty)
                  .join(' · '),
              style: const TextStyle(color: Brand.muted)),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(phone, textDirection: TextDirection.ltr),
          ],
          const SizedBox(height: 10),
          if (workspace.can('owner.edit'))
            DropdownButtonFormField<String>(
              initialValue: stage,
              decoration:
                  InputDecoration(labelText: _label('Stage', 'المرحلة')),
              items: ownerStages
                  .map((value) => DropdownMenuItem(
                      value: value, child: Text(_stageLabel(value))))
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await AgencyService.instance
                    .setOwnerStage('${owner['id']}', value);
                await _load();
              },
            ),
          if (workspace.can('team.manage')) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue:
                  roster.any((m) => m['user_id'] == owner['assigned_to'])
                      ? owner['assigned_to']?.toString()
                      : null,
              decoration:
                  InputDecoration(labelText: _label('Assigned to', 'المسؤول')),
              items: roster
                  .map((member) => DropdownMenuItem(
                      value: '${member['user_id']}',
                      child:
                          Text('${member['name'] ?? member['phone'] ?? ''}')))
                  .toList(),
              onChanged: (value) async {
                await AgencyService.instance
                    .assignOwner('${owner['id']}', value);
                await _load();
              },
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _addOwner() async {
    final workspace = _workspace!;
    final name = TextEditingController();
    final phone = TextEditingController();
    final area = TextEditingController();
    final property = TextEditingController();
    final price = TextEditingController();
    var sourceKind = 'agent';
    String? assignee;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final canAssignTeam = workspace.can('team.manage');
    final roster = workspace.roster
        .where((member) =>
            member['status'] == 'active' &&
            (canAssignTeam || member['user_id'] == currentUserId))
        .toList();
    if (!canAssignTeam && roster.isNotEmpty) {
      assignee = '${roster.first['user_id']}';
    }
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(_label('Add owner / property', 'إضافة مالك / وحدة')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: InputDecoration(
                      labelText: _label('Owner name', 'اسم المالك'))),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      InputDecoration(labelText: _label('Phone', 'الهاتف'))),
              TextField(
                  controller: area,
                  decoration:
                      InputDecoration(labelText: _label('Area', 'المنطقة'))),
              TextField(
                  controller: property,
                  decoration: InputDecoration(
                      labelText: _label('Property reference', 'مرجع الوحدة'))),
              TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: _label('Asking price', 'السعر المطلوب'))),
              DropdownButtonFormField<String>(
                initialValue: sourceKind,
                decoration: InputDecoration(
                    labelText: _label('Source ownership', 'نوع المصدر')),
                items: [
                  DropdownMenuItem(
                      value: 'agent',
                      child: Text(_label('Agent sourced', 'توريد الموظف'))),
                  if (workspace.can('team.manage'))
                    DropdownMenuItem(
                        value: 'company',
                        child:
                            Text(_label('Company provided', 'مقدم من الشركة'))),
                ],
                onChanged: (value) =>
                    setDialogState(() => sourceKind = value ?? 'agent'),
              ),
              DropdownButtonFormField<String>(
                initialValue: assignee,
                decoration:
                    InputDecoration(labelText: _label('Assignee', 'المسؤول')),
                items: roster
                    .map((member) => DropdownMenuItem(
                        value: '${member['user_id']}',
                        child:
                            Text('${member['name'] ?? member['phone'] ?? ''}')))
                    .toList(),
                onChanged: (value) => setDialogState(() => assignee = value),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('cancel'))),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().length < 2) return;
                await AgencyService.instance.createOwner(
                  '${workspace.agency['id']}',
                  {
                    'p_name': name.text.trim(),
                    'p_phone':
                        phone.text.trim().isEmpty ? null : phone.text.trim(),
                    'p_area':
                        area.text.trim().isEmpty ? null : area.text.trim(),
                    'p_property_ref': property.text.trim().isEmpty
                        ? null
                        : property.text.trim(),
                    'p_asking_price': num.tryParse(price.text.trim()),
                    'p_source_kind': sourceKind,
                    'p_assigned_to': assignee,
                  },
                );
                if (context.mounted) Navigator.pop(context);
                await _load();
              },
              child: Text(tr('save')),
            ),
          ],
        );
      }),
    );
    for (final controller in [name, phone, area, property, price]) {
      controller.dispose();
    }
  }
}

class _CreateAgency extends StatefulWidget {
  const _CreateAgency({required this.onCreated});
  final Future<void> Function() onCreated;
  @override
  State<_CreateAgency> createState() => _CreateAgencyState();
}

class _CreateAgencyState extends State<_CreateAgency> {
  final controller = TextEditingController();
  bool saving = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.business_rounded, size: 52, color: Brand.navy),
          const SizedBox(height: 16),
          Text(_label('Create your agency workspace', 'أنشئ مساحة عمل الوكالة'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
              controller: controller,
              decoration: InputDecoration(
                  labelText: _label('Agency name', 'اسم الوكالة'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (controller.text.trim().length < 2) return;
                    setState(() => saving = true);
                    await AgencyService.instance
                        .createAgency(controller.text.trim());
                    await widget.onCreated();
                  },
            child: Text(_label('Create agency', 'إنشاء الوكالة')),
          ),
        ]),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: retry,
                child: Text(_label('Retry', 'إعادة المحاولة'))),
          ]),
        ),
      );
}
