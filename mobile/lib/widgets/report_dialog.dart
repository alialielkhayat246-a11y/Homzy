import 'package:flutter/material.dart';

import '../i18n.dart';

class ReportDraft {
  const ReportDraft(this.reason, this.details);
  final String reason;
  final String? details;
}

Future<ReportDraft?> showReportDialog(BuildContext context) async {
  var reason = 'spam';
  final details = TextEditingController();
  final result = await showDialog<ReportDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('report_content')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: InputDecoration(labelText: tr('report_reason')),
                items: const [
                  ('spam', 'report_spam'),
                  ('harassment', 'report_harassment'),
                  ('fraud', 'report_fraud'),
                  ('inappropriate', 'report_inappropriate'),
                  ('other', 'report_other'),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.$1,
                          child: Text(tr(item.$2)),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => reason = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: details,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(labelText: tr('report_details')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('cancel'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              context,
              ReportDraft(reason,
                  details.text.trim().isEmpty ? null : details.text.trim()),
            ),
            icon: const Icon(Icons.flag_outlined),
            label: Text(tr('send_report')),
          ),
        ],
      ),
    ),
  );
  details.dispose();
  return result;
}
