import 'package:flutter/material.dart';

import '../../domain/app_design.dart';
import '../../domain/booking.dart';
import '../../l10n/app_localizations.dart';
import '../design/chalk/chalk_extras.dart';
import '../design/coaster/coaster_extras.dart';
import '../design/design.dart';
import '../theme.dart';

/// "Kim: 2× Apfelschorle gebucht" with "Rückgängig" and a bar draining over
/// the undo window, one step per second. Kreidetafel pins it as a paper
/// note, Bierdeckel slides it in from the top as a till receipt.
class UndoBanner extends StatelessWidget {
  const UndoBanner({
    required this.text,
    required this.secondsLeft,
    required this.onUndo,
    this.design = AppDesign.standard,
    super.key,
  });

  final AppDesign design;

  final String text;
  final int secondsLeft;

  /// `null` while an undo is being written.
  final VoidCallback? onUndo;

  /// Share of the undo window still left, as the line shows it.
  double get _left =>
      ((secondsLeft - 1) / kUndoWindow.inSeconds).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => switch (design) {
    AppDesign.standard => _standard(context),
    AppDesign.kreidetafel => _note(context),
    AppDesign.bierdeckel => _receipt(context),
  };

  Widget _note(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ChalkNote(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chalkStyle(tokens, 28, color: kChalkNoteInk),
                    ),
                  ),
                  const SizedBox(width: 18),
                  ChalkBox(
                    color: kChalkNoteInk,
                    onTap: onUndo,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(
                      AppLocalizations.of(context).nameListUndoButton,
                      style: chalkStyle(tokens, 26, color: kChalkNoteInk),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: SizedBox(
                key: const Key('undo-banner-progress'),
                height: 3,
                child: DrainingLine(left: _left, color: kChalkNoteInk),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receipt(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: SlideInFromTop(
        child: TillReceipt(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: receiptStyle(17),
                      ),
                    ),
                    const SizedBox(width: 16),
                    CoasterButton(
                      label: AppLocalizations.of(context).nameListUndoButton,
                      primary: true,
                      onTap: onUndo,
                      fontSize: 19,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: SizedBox(
                  key: const Key('undo-banner-progress'),
                  height: 3,
                  child: DrainingLine(left: _left, color: tokens.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _standard(BuildContext context) {
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

/// A line that shrinks to [left] of its width within a second; drawn
/// scaled, so it never lays out again.
class DrainingLine extends StatelessWidget {
  const DrainingLine({required this.left, required this.color, super.key});

  final double left;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Animates every frame: repaint only the line, not the screen.
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: left),
        duration: const Duration(seconds: 1),
        builder: (context, value, child) => Transform.scale(
          scaleX: value,
          alignment: Alignment.centerLeft,
          child: child,
        ),
        child: ColoredBox(color: color, child: const SizedBox.expand()),
      ),
    );
  }
}

/// Short note after an undo attempt, e.g. "Buchung zurückgenommen".
class UndoInfo extends StatelessWidget {
  const UndoInfo(this.text, {this.design = AppDesign.standard, super.key});

  final String text;
  final AppDesign design;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    switch (design) {
      case AppDesign.standard:
        break;
      case AppDesign.kreidetafel:
        return ChalkNote(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Text(
              text,
              style: chalkStyle(tokens, 28, color: kChalkNoteInk),
            ),
          ),
        );
      case AppDesign.bierdeckel:
        return TillReceipt(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Text(text, style: receiptStyle(17)),
          ),
        );
    }
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
