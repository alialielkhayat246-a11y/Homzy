import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';

Color _stageColor(String s) {
  switch (s) {
    case 'contact':
      return Brand.amber;
    case 'qualified':
    case 'matching':
      return Colors.blue;
    case 'viewing':
      return Brand.coral;
    case 'offer_sent':
    case 'negotiate':
    case 'reservation':
      return Colors.deepPurple;
    case 'closed':
      return Brand.green;
    case 'lost':
      return Brand.muted;
    default:
      return Brand.navy;
  }
}

String _tx(String en, String ar) => Lang.instance.isAr ? ar : en;

String _clientBrief(Client c) => [
      if (c.purpose != null) tr(c.purpose == 'rent' ? 'for_rent' : 'for_sale'),
      if (c.type != null) typeLabel(c.type!),
      if (c.area != null && c.area!.isNotEmpty) c.area!,
      if (c.bedrooms != null) '${c.bedrooms} ${tr('beds_short')}',
      if (c.budget != null) '≤ ${egp(c.budget)}',
    ].join(' · ');

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late Future<List<Client>> _future;
  String _stage = 'all';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _future = ClientService.instance.list());

  Future<void> _add() async {
    final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const ClientFormScreen()));
    if (done == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('clients_title'))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt, color: Colors.white),
        label:
            Text(tr('add_client'), style: const TextStyle(color: Colors.white)),
      ),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _chip('all', tr('tab_all')),
              for (final s in clientStages) _chip(s, tr('stage_$s')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Client>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data!;
              final items = _stage == 'all'
                  ? all
                  : all.where((c) => c.stage == _stage).toList();
              if (items.isEmpty) {
                return Center(
                    child: Text(tr('no_clients'),
                        style: const TextStyle(color: Brand.muted)));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _card(items[i]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _chip(String key, String label) {
    final active = _stage == key;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: active,
        showCheckmark: false,
        label: Text(label,
            style: TextStyle(
                color: active ? Colors.white : Brand.navy,
                fontWeight: FontWeight.w600,
                fontSize: 12.5)),
        selectedColor: Brand.navy,
        backgroundColor: Brand.card,
        side: BorderSide(color: active ? Brand.navy : Brand.line),
        onSelected: (_) => setState(() => _stage = key),
      ),
    );
  }

  Widget _card(Client c) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ClientDetailScreen(client: c)));
        _refresh();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(_clientBrief(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _stageColor(c.stage).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8)),
            child: Text(tr('stage_${c.stage}'),
                style: TextStyle(
                    color: _stageColor(c.stage),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.client});
  final Client client;
  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late String _stage = widget.client.stage;
  late Future<Map<String, dynamic>> _intelligence;

  @override
  void initState() {
    super.initState();
    _reloadIntelligence();
  }

  void _reloadIntelligence() {
    _intelligence = ClientService.instance
        .copilot(widget.client.id, language: Lang.instance.isAr ? 'ar' : 'en');
  }

  Future<void> _wa(String phone) async {
    final p = phone.replaceAll(RegExp(r'[^0-9]'), '');
    await launchUrl(Uri.parse('https://wa.me/$p'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _call(String phone) async => launchUrl(Uri.parse('tel:$phone'));

  Future<void> _delete() async {
    await ClientService.instance.remove(widget.client.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return Scaffold(
      appBar: AppBar(title: Text(c.name), actions: [
        IconButton(
            icon: const Icon(Icons.delete_outline, color: Brand.red),
            onPressed: _delete),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.phone != null && c.phone!.isNotEmpty)
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _wa(c.phone!),
                  icon: const Icon(Icons.chat, size: 18, color: Brand.green),
                  label: Text(tr('whatsapp')),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.green,
                      side: const BorderSide(color: Brand.line)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _call(c.phone!),
                  icon: const Icon(Icons.call, size: 18),
                  label: Text(tr('call')),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.navy,
                      side: const BorderSide(color: Brand.line)),
                ),
              ),
            ]),
          const SizedBox(height: 16),
          Text(tr('client_stage'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in clientStages)
              GestureDetector(
                onTap: () async {
                  await ClientService.instance.setStage(c.id, s);
                  setState(() => _stage = s);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _stage == s ? _stageColor(s) : Brand.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _stage == s ? _stageColor(s) : Brand.line),
                  ),
                  child: Text(tr('stage_$s'),
                      style: TextStyle(
                          color: _stage == s ? Colors.white : Brand.navy,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Brand.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Brand.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('client_brief'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(_clientBrief(c),
                    style: const TextStyle(color: Brand.muted)),
                if (c.notes != null && c.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(c.notes!, style: const TextStyle(height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.auto_awesome, color: Brand.amber),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    _tx('AI Sales Copilot & matching units',
                        'مساعد المبيعات الذكي والوحدات المطابقة'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15))),
            IconButton(
                onPressed: () => setState(_reloadIntelligence),
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: _intelligence,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Card(
                    child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text('${snap.error}',
                        style: const TextStyle(color: Brand.red)),
                    TextButton(
                        onPressed: () => setState(_reloadIntelligence),
                        child: Text(_tx('Retry', 'إعادة المحاولة'))),
                  ]),
                ));
              }
              return _copilotPanel(snap.data ?? const {});
            },
          ),
        ],
      ),
    );
  }

  Widget _copilotPanel(Map<String, dynamic> data) {
    final projects = (data['project_matches'] as List? ?? const []);
    final listings = (data['matches'] as List? ?? const []);
    final action = data['next_best_action'];
    final actionMap = action is Map
        ? Map<String, dynamic>.from(action)
        : const <String, dynamic>{};
    final summary = data['advice'] ?? data['summary'];
    final nextAction = action is String
        ? action
        : actionMap['reason'] ?? actionMap['title'];
    final score = data['lead_score'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: Brand.navy,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(
                      _tx('AI recommendation', 'توصية الذكاء الاصطناعي'),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800))),
              if (score != null) Chip(label: Text('$score/100')),
            ]),
            const SizedBox(height: 8),
            Text(
                '${summary ?? _tx('Complete the saved client requirements to improve recommendations.', 'أكمل احتياجات العميل المحفوظة لتحسين الترشيحات.')}',
                style: const TextStyle(color: Colors.white, height: 1.45)),
            if (nextAction != null) ...[
              const Divider(color: Colors.white24, height: 22),
              Text(_tx('Next action', 'الخطوة التالية'),
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('$nextAction',
                  style: const TextStyle(color: Colors.white, height: 1.45)),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Text(
          _tx('Developer projects matched to saved requirements',
              'مشروعات المطورين المطابقة للاحتياجات المحفوظة'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      if (projects.isEmpty)
        _emptyMatch()
      else
        ...projects.take(10).map(_projectMatch),
      const SizedBox(height: 12),
      Text(_tx('Recorded marketplace units', 'وحدات السوق المسجلة'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      if (listings.isEmpty)
        _emptyMatch()
      else
        ...listings.take(10).map(_listingMatch),
    ]);
  }

  Widget _emptyMatch() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(tr('no_matches_yet'),
            style: const TextStyle(color: Brand.muted)),
      );

  Widget _projectMatch(dynamic raw) {
    final item = Map<String, dynamic>.from(raw as Map);
    final project = item['project'] is Map
        ? Map<String, dynamic>.from(item['project'] as Map)
        : const <String, dynamic>{};
    final unit = item['unit'] is Map
        ? Map<String, dynamic>.from(item['unit'] as Map)
        : const <String, dynamic>{};
    final name = item['display_name'] ??
        item['name'] ??
        (Lang.instance.isAr ? project['name_ar'] : project['name']) ??
        project['name'] ??
        'Homzy';
    return Card(
        child: ListTile(
      leading: CircleAvatar(child: Text('${item['score'] ?? 0}%')),
      title: Text('$name', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        project['area'],
        unit['type'],
        if (item['fit_summary'] != null) item['fit_summary'],
      ].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
    ));
  }

  Widget _listingMatch(dynamic raw) {
    final item = Map<String, dynamic>.from(raw as Map);
    final property = item['property'] is Map
        ? Map<String, dynamic>.from(item['property'] as Map)
        : const <String, dynamic>{};
    return Card(
        child: ListTile(
      leading: CircleAvatar(child: Text('${item['score'] ?? 0}%')),
      title: Text('${property['title'] ?? property['compound'] ?? 'Homzy'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([property['area'], property['type'], property['price']]
          .where((v) => v != null && '$v'.isNotEmpty)
          .join(' · ')),
    ));
  }
}

class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key});
  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _beds = TextEditingController();
  final _budget = TextEditingController();
  final _notes = TextEditingController();
  String _purpose = 'sale';
  String? _type;
  bool _saving = false;

  static const _types = [
    'apartment',
    'studio',
    'duplex',
    'penthouse',
    'villa',
    'townhouse',
    'twinhouse',
    'chalet',
  ];

  @override
  void dispose() {
    for (final c in [_name, _phone, _area, _beds, _budget, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('client_name_required'))));
      return;
    }
    setState(() => _saving = true);
    try {
      await ClientService.instance.create({
        'name': _name.text.trim(),
        'phone': _t(_phone),
        'purpose': _purpose,
        'type': _type,
        'area': _t(_area),
        'bedrooms': int.tryParse(_beds.text.trim()),
        'budget': num.tryParse(_budget.text.replaceAll(',', '').trim()),
        'notes': _t(_notes),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _saving = false);
      }
    }
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('add_client'))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        _field(_name, tr('client_name')),
        const SizedBox(height: 12),
        _field(_phone, tr('client_phone'), keyboard: TextInputType.phone),
        const SizedBox(height: 12),
        Row(children: [
          for (final p in const ['sale', 'rent'])
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _purpose = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _purpose == p ? Brand.navy : Brand.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _purpose == p ? Brand.navy : Brand.line),
                    ),
                    child: Text(p == 'sale' ? tr('for_sale') : tr('for_rent'),
                        style: TextStyle(
                            color: _purpose == p ? Colors.white : Brand.navy,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('property_type')),
          items: _types
              .map((t) => DropdownMenuItem(value: t, child: Text(typeLabel(t))))
              .toList(),
          onChanged: (v) => setState(() => _type = v),
        ),
        const SizedBox(height: 12),
        _field(_area, tr('filter_area')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _field(_beds, tr('lst_beds'),
                  keyboard: TextInputType.number)),
          const SizedBox(width: 10),
          Expanded(
              child: _field(_budget, tr('client_budget'),
                  keyboard: TextInputType.number)),
        ]),
        const SizedBox(height: 12),
        _field(_notes, tr('client_notes'), maxLines: 3),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(tr('save')),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label,
          {int maxLines = 1, TextInputType? keyboard}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
      );
}
