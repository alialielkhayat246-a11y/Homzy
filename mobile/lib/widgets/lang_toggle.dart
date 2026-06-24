import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

/// Small AR/EN switch. Shows the language you'd switch TO.
class LangToggle extends StatelessWidget {
  const LangToggle({super.key, this.onSurface = false});

  /// Use light styling when placed on a dark/navy surface.
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final fg = onSurface ? Colors.white : Brand.navy;
    final border = onSurface ? Colors.white24 : Brand.line;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Lang.instance.toggle(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 16, color: fg.withValues(alpha: 0.8)),
            const SizedBox(width: 5),
            Text(
              Lang.instance.isAr ? 'EN' : 'ع',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: fg, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
