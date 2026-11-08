import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dto.dart';
import '../../domain/catalog.dart';
import '../../domain/master_data.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../format.dart';
import '../providers.dart';
import 'active_segments_header.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'master_data_save.dart';

List<PriceTier> _sortedTiers(Catalog catalog) =>
    [...catalog.tiers]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

/// Drinks of the catalog: create, edit prices, deactivate, reorder per group.
class DrinksScreen extends ConsumerStatefulWidget {
  const DrinksScreen({super.key});

  @override
  ConsumerState<DrinksScreen> createState() => _DrinksScreenState();
}

class _DrinksScreenState extends ConsumerState<DrinksScreen> {
  bool _showActive = true;

  /// Optimistic order (all drink ids) per group while a reorder request runs.
  final Map<String, List<String>> _pending = {};

  /// The session ended (server restart, expiry): back to the gate, which
  /// shows the PIN prompt. Already gone when the idle logout left the area.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Future<void> _open(Catalog catalog, Drink? drink) {
    return showDialog<void>(
      context: context,
      builder: (_) => AdminIdleGuard(
        child: DrinkDialog(catalog: catalog, drink: drink),
      ),
    );
  }

  /// All drinks of [groupId] (active and deactivated) in display order.
  List<Drink> _ordered(Catalog catalog, String groupId) {
    final drinks = [
      for (final d in catalog.drinks)
        if (d.groupId == groupId) d,
    ];
    final pending = _pending[groupId];
    if (pending != null && pending.length == drinks.length) {
      final byId = {for (final d in drinks) d.id: d};
      if (pending.every(byId.containsKey)) {
        return [for (final id in pending) byId[id]!];
      }
    }
    return drinks..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  }

  Future<void> _reorder(
    Catalog catalog,
    String groupId,
    int oldIndex,
    int newIndex,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final all = _ordered(catalog, groupId);
    final shown = [
      for (final d in all)
        if (d.isActive == _showActive) d,
    ];
    if (newIndex == oldIndex) return;
    shown.insert(newIndex, shown.removeAt(oldIndex));
    // Drinks of the other segment keep their slots.
    final queue = shown.iterator;
    final ids = [
      for (final d in all)
        if (d.isActive == _showActive) (queue..moveNext()).current.id else d.id,
    ];
    setState(() => _pending[groupId] = ids);
    final result = await saveMasterData(
      ref,
      l10n,
      (api, token) => api.reorderDrinks(token, groupId, ids),
    );
    if (!mounted) return;
    if (_pending[groupId] == ids) setState(() => _pending.remove(groupId));
    if (result case SaveFailed(:final message)) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(catalogProvider).value;
    final activeCount = catalog?.drinks.where((d) => d.isActive).length ?? 0;
    final inactiveCount = (catalog?.drinks.length ?? 0) - activeCount;
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.drinksTitle)),
        body: catalog == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ActiveSegmentsHeader(
                    segmentsKey: const Key('drinks-segments'),
                    newKey: const Key('drink-new'),
                    newLabel: l10n.drinksNew,
                    showActive: _showActive,
                    activeCount: activeCount,
                    inactiveCount: inactiveCount,
                    onChanged: (v) => setState(() => _showActive = v),
                    // A drink needs a group.
                    onNew: catalog.groups.isEmpty
                        ? null
                        : () => _open(catalog, null),
                    newHint: catalog.groups.isEmpty
                        ? l10n.drinksNeedGroup
                        : null,
                  ),
                  Expanded(child: _list(l10n, catalog)),
                ],
              ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n, Catalog catalog) {
    final tokens = DesignTokens.of(context);
    final tiers = _sortedTiers(catalog);
    final groups = [...catalog.groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        for (final group in groups)
          ..._section(l10n, catalog, tiers, group, tokens),
      ],
    );
  }

  List<Widget> _section(
    AppLocalizations l10n,
    Catalog catalog,
    List<PriceTier> tiers,
    DrinkGroup group,
    DesignTokens tokens,
  ) {
    final shown = [
      for (final d in _ordered(catalog, group.id))
        if (d.isActive == _showActive) d,
    ];
    if (shown.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(
          group.name,
          style: TextStyle(color: tokens.muted, fontSize: 18),
        ),
      ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (o, n) => _reorder(catalog, group.id, o, n),
        children: [
          for (final (i, d) in shown.indexed)
            ListTile(
              key: Key('drink-${d.id}'),
              title: Text(d.name, style: const TextStyle(fontSize: 22)),
              subtitle: Text(
                l10n.drinkRow(
                  d.crateSize,
                  [
                    for (final t in tiers)
                      d.prices[t.id] == null
                          ? '–'
                          : formatCents(d.prices[t.id]!),
                  ].join(' / '),
                ),
                style: const TextStyle(fontSize: 16),
              ),
              trailing: ReorderableDragStartListener(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.drag_handle,
                    key: Key('drink-handle-${d.id}'),
                    size: 32,
                  ),
                ),
              ),
              onTap: () => _open(catalog, d),
            ),
        ],
      ),
    ];
  }
}

/// Create ([drink] null) or edit a drink. Deactivating or reactivating is
/// saved at once with the current field values.
class DrinkDialog extends ConsumerStatefulWidget {
  const DrinkDialog({super.key, required this.catalog, this.drink});

  final Catalog catalog;
  final Drink? drink;

  @override
  ConsumerState<DrinkDialog> createState() => _DrinkDialogState();
}

class _DrinkDialogState extends ConsumerState<DrinkDialog> {
  late final TextEditingController _name;
  late final TextEditingController _crate;
  late String _groupId;
  late bool _hidden;

  /// One field per price tier id; created when a tier first shows up, so a
  /// tier added meanwhile gets an empty field and the other entries stay.
  final Map<String, TextEditingController> _prices = {};
  String? _error;
  bool _busy = false;

  /// The live catalog; the dialog's own catalog until it has loaded.
  Catalog _catalogOf(WidgetRef ref, {bool watch = true}) =>
      (watch ? ref.watch(catalogProvider) : ref.read(catalogProvider)).value ??
      widget.catalog;

  @override
  void initState() {
    super.initState();
    final d = widget.drink;
    _name = TextEditingController(text: d?.name ?? '');
    _crate = TextEditingController(text: d == null ? '' : '${d.crateSize}');
    final groups = [...widget.catalog.groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _groupId = d?.groupId ?? groups.first.id;
    _hidden = d?.isHidden ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _crate.dispose();
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _priceField(String tierId) =>
      _prices.putIfAbsent(tierId, () {
        final cents = widget.drink?.prices[tierId];
        return TextEditingController(
          text: cents == null ? '' : formatCentsPlain(cents),
        );
      });

  String? get _clean => cleanName(_name.text, maxDrinkName);

  int? get _crateSize {
    final n = int.tryParse(_crate.text.trim());
    return n != null && n >= 1 ? n : null;
  }

  /// Cents per tier id, or null while a tier has no valid price.
  Map<String, int>? _pricesOrNull(List<PriceTier> tiers) {
    final result = <String, int>{};
    for (final t in tiers) {
      final cents = parseEuroCents(_priceField(t.id).text);
      if (cents == null) return null;
      result[t.id] = cents;
    }
    return result;
  }

  bool _taken(Catalog catalog) {
    final clean = _clean;
    return clean != null &&
        nameTaken(clean, [
          for (final d in catalog.drinks) (id: d.id, name: d.name),
        ], exceptId: widget.drink?.id);
  }

  Future<void> _save({bool? isActive}) async {
    final catalog = _catalogOf(ref, watch: false);
    final name = _clean;
    final crate = _crateSize;
    final prices = _pricesOrNull(_sortedTiers(catalog));
    if (name == null || crate == null || prices == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final existing = widget.drink;
    final dto = DrinkWriteDto(
      name: name,
      groupId: _groupId,
      crateSize: crate,
      isHidden: _hidden,
      prices: prices,
      isActive: existing == null ? null : (isActive ?? existing.isActive),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await saveMasterData(ref, l10n, (api, token) async {
      if (existing == null) {
        await api.createDrink(token, dto);
      } else {
        await api.updateDrink(token, existing.id, dto);
      }
    });
    if (!mounted) return;
    switch (result) {
      case Saved():
        Navigator.of(context).pop();
      case SaveFailed(:final message, :final detail):
        if (detail == 'prices_incomplete') {
          // The tiers changed: reload so new ones show up as empty fields.
          await refreshCatalog(ref);
          if (!mounted) return;
        }
        setState(() {
          _busy = false;
          _error = detail == 'prices_incomplete'
              ? l10n.drinkPricesIncomplete
              : message;
        });
      case SaveSessionEnded():
        // The screen's session listener leaves the admin area.
        break;
    }
  }

  void _edited() => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final existing = widget.drink;
    final catalog = _catalogOf(ref);
    final tiers = _sortedTiers(catalog);
    final groups = [...catalog.groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final taken = _taken(catalog);
    final canSave =
        !_busy &&
        _clean != null &&
        !taken &&
        _crateSize != null &&
        _pricesOrNull(tiers) != null;
    return AlertDialog(
      title: Text(
        existing == null ? l10n.drinkDialogNew : l10n.drinkDialogEdit,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('drink-name'),
                controller: _name,
                maxLength: maxDrinkName,
                onChanged: (_) => _edited(),
                decoration: InputDecoration(
                  labelText: l10n.drinkFieldName,
                  errorText: taken ? l10n.saveNameTaken : null,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('drink-group'),
                initialValue: _groupId,
                decoration: InputDecoration(labelText: l10n.drinkFieldGroup),
                items: [
                  for (final g in groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _groupId = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('drink-crate'),
                controller: _crate,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _edited(),
                decoration: InputDecoration(labelText: l10n.drinkFieldCrate),
              ),
              const SizedBox(height: 16),
              Text(l10n.drinkFieldPrices),
              for (final t in tiers)
                TextField(
                  key: Key('drink-price-${t.id}'),
                  controller: _priceField(t.id),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _edited(),
                  decoration: InputDecoration(
                    labelText: t.name,
                    suffixText: '€',
                  ),
                ),
              CheckboxListTile(
                key: const Key('drink-hidden'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _hidden,
                onChanged: (v) => setState(() => _hidden = v ?? false),
                title: Text(l10n.drinkHidden),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('drink-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            key: const Key('drink-toggle-active'),
            onPressed: canSave
                ? () => _save(isActive: !existing.isActive)
                : null,
            child: Text(
              existing.isActive ? l10n.masterDeactivate : l10n.masterActivate,
            ),
          ),
        TextButton(
          key: const Key('drink-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          key: const Key('drink-save'),
          onPressed: canSave ? _save : null,
          child: Text(l10n.dialogSave),
        ),
      ],
    );
  }
}
