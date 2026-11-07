import 'package:flutter/painting.dart';

import '../../domain/catalog.dart';

/// Everything a design's drink board shows and does for one person; built
/// once by the drink selection screen.
class DrinkBoardData {
  const DrinkBoardData({
    required this.groups,
    required this.priceOf,
    required this.colorOf,
    required this.quantities,
    required this.favourites,
    required this.favouritesEnabled,
    required this.favouritesDimmed,
    required this.onTap,
    required this.onFavouriteTap,
  });

  /// Groups in sort order with the drinks priced for the person.
  final List<(DrinkGroup, List<Drink>)> groups;

  /// The person's price of a drink on the board (groups and favourites).
  final int Function(Drink) priceOf;

  /// The colour of a drink's group.
  final Color Function(Drink) colorOf;

  /// Pending quantity per drink id.
  final Map<String, int> quantities;

  /// Favourite drinks in rank order; empty hides the favourites.
  final List<Drink> favourites;

  /// Favourites take taps (no grid order, commit or sheet).
  final bool favouritesEnabled;

  /// Favourites are greyed out (a grid order is pending or a sheet is open).
  final bool favouritesDimmed;

  /// A grid tap: adds one unit to the order.
  final void Function(Drink drink, int priceCents) onTap;

  /// A favourite tap: books one unit at once.
  final void Function(Drink drink, int priceCents) onFavouriteTap;
}
