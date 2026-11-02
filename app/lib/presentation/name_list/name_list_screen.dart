import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// Stub; the real name list is built in Task 9.
class NameListScreen extends ConsumerWidget {
  const NameListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Text(
          AppLocalizations.of(context).nameListTitle,
          style: Theme.of(context).textTheme.displayMedium,
        ),
      ),
    );
  }
}
