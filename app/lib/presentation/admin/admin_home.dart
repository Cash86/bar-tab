import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import 'admin_bookings_screen.dart';
import 'design_screen.dart';
import 'drinks_screen.dart';
import 'persons_screen.dart';

/// Pushes an admin [screen]. All admin tiles use this, so the idle guard's
/// `didPopNext` re-arms when the screen is left.
void openAdminScreen(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

typedef _TileSpec = ({
  String name,
  String Function(AppLocalizations) label,
  String Function(AppLocalizations)? subtitle,
  Widget Function() screen,
});

/// The admin functions as tiles; a new function is one more entry.
final List<_TileSpec> _tiles = [
  (
    name: 'bookings',
    label: (l) => l.adminBookings,
    subtitle: (l) => l.adminTileBookingsSubtitle,
    screen: () => const AdminBookingsScreen(),
  ),
  (
    name: 'design',
    label: (l) => l.designTitle,
    subtitle: (l) => l.adminTileDesignSubtitle,
    screen: () => const DesignScreen(),
  ),
  (
    name: 'persons',
    label: (l) => l.personsTitle,
    subtitle: (l) => l.adminTilePersonsSubtitle,
    screen: () => const PersonsScreen(),
  ),
  (
    name: 'drinks',
    label: (l) => l.drinksTitle,
    subtitle: (l) => l.adminTileDrinksSubtitle,
    screen: () => const DrinksScreen(),
  ),
];

/// Tile grid of the admin area, shown once the PIN was accepted.
class AdminHome extends ConsumerWidget {
  const AdminHome({super.key, this.onRepair});

  /// Re-pairing with the server; the link is disabled while null.
  final VoidCallback? onRepair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2,
              children: [
                for (final tile in _tiles)
                  _Tile(
                    key: Key('admin-tile-${tile.name}'),
                    label: tile.label(l10n),
                    subtitle: tile.subtitle?.call(l10n),
                    onTap: () => openAdminScreen(context, tile.screen()),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('admin-repair'),
              onPressed: onRepair,
              child: Text(l10n.adminRepair),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final subtitle = this.subtitle;
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: tokens.text, fontSize: 24)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: tokens.muted, fontSize: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
