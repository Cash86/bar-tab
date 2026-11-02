import 'package:flutter/material.dart';

import '../../domain/booking.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';

/// "Kim: 2× Apfelschorle gebucht" with "Rückgängig" and a bar draining over
/// the undo window, one step per second.
class UndoBanner extends StatelessWidget {
  const UndoBanner({
    required this.text,
    required this.secondsLeft,
    required this.onUndo,
    super.key,
  });

  final String text;
  final int secondsLeft;

  /// `null` while an undo is being written.
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    const ink = BarTabTheme.bottle;
    final window = kUndoWindow.inSeconds;
    return Material(
      color: BarTabTheme.collectiveAccent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 18,
                        fontVariations: [FontVariation('wght', 700)],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Material(
                    color: ink,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onUndo,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        child: Text(
                          AppLocalizations.of(context).nameListUndoButton,
                          style: const TextStyle(
                            color: BarTabTheme.paper,
                            fontSize: 18,
                            fontVariations: [FontVariation('wght', 700)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              key: const Key('undo-banner-progress'),
              height: 5,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(seconds: 1),
                alignment: Alignment.centerLeft,
                widthFactor: ((secondsLeft - 1) / window).clamp(0.0, 1.0),
                child: const ColoredBox(color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short note after an undo attempt, e.g. "Buchung zurückgenommen".
class UndoInfo extends StatelessWidget {
  const UndoInfo(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BarTabTheme.paper,
      borderRadius: BorderRadius.circular(10),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(
          text,
          style: const TextStyle(
            color: BarTabTheme.bottle,
            fontSize: 18,
            fontVariations: [FontVariation('wght', 700)],
          ),
        ),
      ),
    );
  }
}
