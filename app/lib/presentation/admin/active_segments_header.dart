import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Header of an admin list: the Aktiv/Deaktiviert switch and the button that
/// creates a new entry.
class ActiveSegmentsHeader extends StatelessWidget {
  const ActiveSegmentsHeader({
    super.key,
    required this.segmentsKey,
    required this.newKey,
    required this.newLabel,
    required this.showActive,
    required this.activeCount,
    required this.inactiveCount,
    required this.onChanged,
    required this.onNew,
  });

  final Key segmentsKey;
  final Key newKey;
  final String newLabel;
  final bool showActive;
  final int activeCount;
  final int inactiveCount;
  final ValueChanged<bool> onChanged;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          SegmentedButton<bool>(
            key: segmentsKey,
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: true,
                label: Text(l10n.segmentActive(activeCount)),
              ),
              ButtonSegment(
                value: false,
                label: Text(l10n.segmentInactive(inactiveCount)),
              ),
            ],
            selected: {showActive},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
          const Spacer(),
          FilledButton(key: newKey, onPressed: onNew, child: Text(newLabel)),
        ],
      ),
    );
  }
}
