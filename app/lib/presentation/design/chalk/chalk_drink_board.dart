import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/catalog.dart';
import '../../../l10n/app_localizations.dart';
import '../../drinks/drink_board_data.dart';
import '../../drinks/order_bar.dart';
import '../../format.dart';
import '../chalk_plan.dart';
import '../chalk_text.dart';
import '../design.dart';
import 'chalk_board.dart';
import 'chalk_extras.dart';

/// Width of the "Für dich" board.
const double kChalkFavouritesWidth = 236;

const double _gap = 22;
const double _boxColumnGap = 10;

/// The Kreidetafel drink selection: the "Für dich" board on the left, one
/// chalk field per group on the right (see [planChalkBoard]).
class ChalkDrinkBoard extends StatelessWidget {
  const ChalkDrinkBoard(this.data, {super.key});

  final DrinkBoardData data;

  @override
  Widget build(BuildContext context) {
    // The order countdown animates every frame next to the board.
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.favourites.isNotEmpty) ...[
              Padding(
                // Clear of the order bar, like the fields.
                padding: const EdgeInsets.only(bottom: kBoardOrderBarRoom),
                child: SizedBox(
                  width: kChalkFavouritesWidth,
                  child: _Favourites(data),
                ),
              ),
              const SizedBox(width: _gap),
            ],
            Expanded(child: _Fields(data)),
          ],
        ),
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields(this.data);

  final DrinkBoardData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(
          constraints.maxWidth,
          math.max(0, constraints.maxHeight - kBoardOrderBarRoom),
        );
        final plan = planChalkBoard([
          for (final (_, drinks) in data.groups) drinks.length,
        ], area);
        final height = plan.fields.fold<double>(
          0,
          (h, f) => math.max(h, f.rect.bottom),
        );
        final board = SizedBox(
          width: area.width,
          height: height,
          child: Stack(
            children: [
              for (var i = 0; i < plan.fields.length; i++)
                Positioned.fromRect(
                  rect: plan.fields[i].rect,
                  child: _Field(
                    key: ValueKey('chalk-field-${data.groups[i].$1.id}'),
                    group: data.groups[i].$1,
                    drinks: data.groups[i].$2,
                    field: plan.fields[i],
                    data: data,
                  ),
                ),
            ],
          ),
        );
        if (!plan.scrolls) {
          return Align(alignment: Alignment.topLeft, child: board);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: kBoardOrderBarRoom),
          child: board,
        );
      },
    );
  }
}

/// One group: underlined heading, then its drinks as chalk boxes.
class _Field extends StatefulWidget {
  const _Field({
    super.key,
    required this.group,
    required this.drinks,
    required this.field,
    required this.data,
  });

  final DrinkGroup group;
  final List<Drink> drinks;
  final ChalkField field;
  final DrinkBoardData data;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  /// The fitted name size and what it was fitted for: the screen rebuilds
  /// on every tap and every second while an order is pending.
  (List<Object?>, double)? _size;

  List<Drink> get drinks => widget.drinks;
  ChalkField get field => widget.field;
  DrinkBoardData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final group = widget.group;
    return CustomPaint(
      painter: ChalkBorderPainter(color: tokens.text.withAlpha(140)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: kChalkHeader,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChalkText(
                  group.name,
                  style: chalkStyle(tokens, 28).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: Color(group.color),
                    decorationThickness: 2,
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _boxes(
                  tokens,
                  _nameSize(context, tokens, constraints.maxWidth),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boxes(DesignTokens tokens, double nameSize) {
    final columns = field.boxColumns;
    final rows = <Widget>[
      for (var i = 0; i < drinks.length; i += columns)
        Padding(
          // Packed from the top only when the field scrolls.
          padding: EdgeInsets.only(bottom: field.scrolls ? kChalkBoxGap : 0),
          child: Row(
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: _boxColumnGap),
                Expanded(
                  child: i + j < drinks.length
                      ? _box(drinks[i + j], nameSize)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
    ];
    return field.scrolls
        ? SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(children: rows),
          )
        // Boxes are capped in height; even gaps fill the field (half a gap
        // at the edges keeps boxes near the heading).
        : Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: rows,
          );
  }

  /// One name size for the whole field: the largest at which every name
  /// fits its box in up to two lines next to its price.
  double _nameSize(BuildContext context, DesignTokens tokens, double width) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final key = <Object?>[
      for (final d in drinks) ...[d.name, data.priceOf(d)],
      width,
      field.boxHeight,
      field.boxColumns,
      base,
      scaler,
      tokens,
    ];
    if (_size case (final k, final size) when listEquals(k, key)) return size;
    final size = _fitNames(tokens, base, scaler, width);
    _size = (key, size);
    return size;
  }

  double _fitNames(
    DesignTokens tokens,
    TextStyle base,
    TextScaler scaler,
    double width,
  ) {
    final scale = field.boxHeight / kChalkBoxHeight;
    final columns = field.boxColumns;
    final boxWidth = (width - (columns - 1) * _boxColumnGap) / columns;
    final nameStyle = base.merge(
      chalkStyle(tokens, _DrinkBox.nameBase * scale),
    );
    final priceStyle = base.merge(_DrinkBox.priceStyle(tokens, scale));
    var size = nameStyle.fontSize!;
    for (final drink in drinks) {
      final price = TextPainter(
        text: TextSpan(
          text: formatCents(data.priceOf(drink)),
          style: priceStyle,
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      // One px to spare for rounding in the row's layout.
      final nameWidth =
          boxWidth -
          2 * _DrinkBox.padding -
          _DrinkBox.priceGap -
          price.width -
          1;
      price.dispose();
      size = math.min(
        size,
        fitChalkFontSize(
          drink.name,
          nameStyle,
          Size(math.max(0, nameWidth), field.boxHeight),
          minFontSize: _DrinkBox.minName,
          maxLines: 2,
          textScaler: scaler,
        ),
      );
    }
    return size;
  }

  Widget _box(Drink drink, double nameSize) {
    final price = data.priceOf(drink);
    return _DrinkBox(
      key: ValueKey('drink-${drink.id}'),
      name: drink.name,
      priceCents: price,
      quantity: data.quantities[drink.id] ?? 0,
      height: field.boxHeight,
      nameSize: nameSize,
      onTap: () => data.onTap(drink, price),
    );
  }
}

/// "name … price" in a dashed chalk box; a count badge on its corner once
/// ordered.
class _DrinkBox extends StatelessWidget {
  const _DrinkBox({
    required this.name,
    required this.priceCents,
    required this.quantity,
    required this.height,
    required this.nameSize,
    required this.onTap,
    super.key,
  });

  /// Name size at the base box height, before the field fits it.
  static const nameBase = 23.0;
  static const minName = 14.0;
  static const padding = 10.0;
  static const priceGap = 6.0;

  /// Grows less than the name: narrow fields need the width for the name.
  static TextStyle priceStyle(DesignTokens tokens, double scale) =>
      chalkStyle(tokens, math.min(21 * scale, 24), color: tokens.accent);

  final String name;
  final int priceCents;
  final int quantity;

  /// Box height from the plan; the lettering grows with it.
  final double height;

  /// The field's name size (see [_FieldState._nameSize]).
  final double nameSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final picked = quantity > 0;
    final scale = height / kChalkBoxHeight;
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: ChalkBorderPainter(
                color: tokens.text.withAlpha(153),
                dashed: true,
                fill: picked ? tokens.text.withAlpha(36) : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const RoundedRectangleBorder(
                    borderRadius: kChalkCorners,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: padding),
                    child: Row(
                      children: [
                        Expanded(
                          child: ChalkText(
                            name,
                            style: chalkStyle(tokens, nameSize),
                            // The field already fitted the size.
                            minFontSize: nameSize,
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(width: priceGap),
                        Text(
                          formatCents(priceCents),
                          style: priceStyle(tokens, scale),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (picked)
            Positioned(
              top: -10,
              right: -8,
              child: IgnorePointer(child: _Badge(quantity)),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.quantity);

  final int quantity;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        '$quantity',
        style: chalkStyle(
          tokens,
          21,
          color: tokens.onAccent,
          height: 1,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// The specials board: yellow double frame, ★ title, hung slightly crooked;
/// inert and dimmed like Standard's quick bar.
class _Favourites extends StatelessWidget {
  const _Favourites(this.data);

  final DrinkBoardData data;

  static const _slots = 4;
  static const _slotGap = 12.0;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final yellow = tokens.accent;
    // Drawn, not a glyph: Caveat has no ★.
    final star = CustomPaint(
      size: const Size.square(22),
      painter: _StarPainter(yellow),
    );
    return IgnorePointer(
      ignoring: !data.favouritesEnabled,
      child: Opacity(
        opacity: data.favouritesDimmed ? 0.35 : 1,
        child: Transform.rotate(
          angle: -math.pi / 180,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: yellow, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: yellow, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.4),
                    colors: [yellow.withAlpha(26), yellow.withAlpha(0)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            star,
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context).favouritesChalk,
                              style: chalkStyle(tokens, 36, color: yellow),
                            ),
                            const SizedBox(width: 8),
                            star,
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // Four slots' height: fewer favourites keep the
                            // same size and spread out.
                            final height =
                                ((constraints.maxHeight -
                                            (_slots - 1) * _slotGap) /
                                        _slots)
                                    .clamp(0.0, 120.0);
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                for (final d in data.favourites)
                                  SizedBox(
                                    height: height,
                                    child: _FavouriteBox(
                                      key: ValueKey('quick-${d.id}'),
                                      name: d.name,
                                      priceCents: data.priceOf(d),
                                      onTap: () => data.onFavouriteTap(
                                        d,
                                        data.priceOf(d),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A favourite in large yellow chalk: name over price.
class _FavouriteBox extends StatelessWidget {
  const _FavouriteBox({
    required this.name,
    required this.priceCents,
    required this.onTap,
    super.key,
  });

  final String name;
  final int priceCents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return CustomPaint(
      painter: ChalkBorderPainter(
        color: tokens.accent,
        width: 2.5,
        fill: tokens.accent.withAlpha(15),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const RoundedRectangleBorder(
            borderRadius: kChalkCorners,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  flex: 3,
                  child: Center(
                    child: ChalkText(
                      name,
                      style: chalkStyle(tokens, 42, height: 1),
                      minFontSize: 18,
                      maxLines: 2,
                    ),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: Center(
                    child: ChalkText(
                      formatCents(priceCents),
                      style: chalkStyle(
                        tokens,
                        28,
                        color: kChalkCollectiveText,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A five-pointed chalk star.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.42;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}
