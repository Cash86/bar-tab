import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../domain/app_design.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import 'admin_idle.dart';

final _log = Logger('admin');

/// Choice of the tablet's design; applies at once.
class DesignScreen extends ConsumerWidget {
  const DesignScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      AppDesign.standard: l10n.designStandard,
      AppDesign.kreidetafel: l10n.designKreidetafel,
      AppDesign.bierdeckel: l10n.designBierdeckel,
    };
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.designTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SegmentedButton<AppDesign>(
              showSelectedIcon: false,
              segments: [
                for (final MapEntry(key: design, value: label)
                    in labels.entries)
                  ButtonSegment(
                    value: design,
                    label: Text(label, key: Key('design-${design.storageKey}')),
                  ),
              ],
              selected: {ref.watch(appDesignProvider)},
              onSelectionChanged: (choice) =>
                  unawaited(_select(ref, choice.single)),
            ),
          ),
        ),
      ),
    );
  }

  /// A failed write keeps the old design; the choice can be tapped again.
  Future<void> _select(WidgetRef ref, AppDesign design) async {
    try {
      await ref.read(appDesignProvider.notifier).select(design);
    } on Object catch (e, st) {
      _log.severe('Storing the design failed', e, st);
    }
  }
}
