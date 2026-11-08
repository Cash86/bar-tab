import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog.dart';
import '../../domain/master_data.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'delete_confirm.dart';
import 'master_data_save.dart';

List<PriceTier> _sortedTiers(Catalog catalog) =>
    [...catalog.tiers]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

int _personCount(Catalog catalog, String tierId) =>
    catalog.persons.where((p) => p.priceTierId == tierId).length;

/// Price tiers: create, rename, delete and reorder.
class TiersScreen extends ConsumerStatefulWidget {
  const TiersScreen({super.key});

  @override
  ConsumerState<TiersScreen> createState() => _TiersScreenState();
}

class _TiersScreenState extends ConsumerState<TiersScreen> {
  /// Optimistic order (all tier ids) while a reorder request runs.
  List<String>? _pending;

  /// The session ended (server restart, expiry): back to the gate, which
  /// shows the PIN prompt. Already gone when the idle logout left the area.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Future<void> _open(PriceTier? tier) {
    return showDialog<void>(
      context: context,
      builder: (_) => AdminIdleGuard(child: TierDialog(tier: tier)),
    );
  }

  List<PriceTier> _ordered(Catalog catalog) {
    final tiers = _sortedTiers(catalog);
    final pending = _pending;
    if (pending != null && pending.length == tiers.length) {
      final byId = {for (final t in tiers) t.id: t};
      if (pending.every(byId.containsKey)) {
        return [for (final id in pending) byId[id]!];
      }
    }
    return tiers;
  }

  Future<void> _reorder(Catalog catalog, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final tiers = _ordered(catalog);
    tiers.insert(newIndex, tiers.removeAt(oldIndex));
    final ids = [for (final t in tiers) t.id];
    setState(() => _pending = ids);
    final result = await saveMasterData(
      ref,
      l10n,
      (api, token) => api.reorderPriceTiers(token, ids),
    );
    if (!mounted) return;
    if (_pending == ids) setState(() => _pending = null);
    if (result case SaveFailed(:final message, :final detail)) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      // Refused (e.g. order_mismatch): the list was stale, so the next
      // attempt must start from the server's current data.
      if (detail != null) await refreshCatalog(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(catalogProvider).value;
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.tiersTitle)),
        body: catalog == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: const Key('tier-new'),
                        onPressed: () => _open(null),
                        child: Text(l10n.tiersNew),
                      ),
                    ),
                  ),
                  Expanded(child: _list(l10n, catalog)),
                ],
              ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n, Catalog catalog) {
    final tokens = DesignTokens.of(context);
    final tiers = _ordered(catalog);
    return ReorderableListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      buildDefaultDragHandles: false,
      onReorderItem: (o, n) => _reorder(catalog, o, n),
      children: [
        for (final (i, t) in tiers.indexed)
          ListTile(
            key: Key('tier-${t.id}'),
            title: Text(t.name, style: const TextStyle(fontSize: 22)),
            subtitle: Text(
              l10n.tierPersonCount(_personCount(catalog, t.id)),
              style: TextStyle(color: tokens.muted, fontSize: 16),
            ),
            trailing: ReorderableDragStartListener(
              index: i,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.drag_handle,
                  key: Key('tier-handle-${t.id}'),
                  size: 32,
                ),
              ),
            ),
            onTap: () => _open(t),
          ),
      ],
    );
  }
}

/// Create ([tier] null) or rename a price tier. A new tier starts with the
/// first tier's prices (the server copies them).
class TierDialog extends ConsumerStatefulWidget {
  const TierDialog({super.key, this.tier});

  final PriceTier? tier;

  @override
  ConsumerState<TierDialog> createState() => _TierDialogState();
}

class _TierDialogState extends ConsumerState<TierDialog> {
  late final TextEditingController _name;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.tier?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _clean => cleanName(_name.text, maxTierName);

  bool _taken(Catalog? catalog) {
    final clean = _clean;
    return clean != null &&
        catalog != null &&
        nameTaken(clean, [
          for (final t in catalog.tiers) (id: t.id, name: t.name),
        ], exceptId: widget.tier?.id);
  }

  /// Shows the outcome of a write; the screen's session listener leaves the
  /// admin area when the session ended.
  void _finish(
    SaveResult? result,
    AppLocalizations l10n, {
    bool deleting = false,
  }) {
    switch (result) {
      case Saved():
        Navigator.of(context).pop();
      case SaveFailed(:final message, :final detail):
        setState(() {
          _busy = false;
          _error = deleting && detail != null
              ? l10n.masterDeleteFailed
              : message;
        });
      case SaveSessionEnded():
        break;
      case null:
        setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final name = _clean;
    if (name == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final existing = widget.tier;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await saveMasterData(ref, l10n, (api, token) async {
      if (existing == null) {
        await api.createPriceTier(token, name);
      } else {
        await api.updatePriceTier(token, existing.id, name);
      }
    });
    if (!mounted) return;
    _finish(result, l10n);
  }

  Future<void> _delete(PriceTier tier) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await confirmAndDelete(
      context,
      ref,
      title: l10n.tierDeleteConfirm(tier.name),
      confirmKey: const Key('tier-delete-confirm'),
      cancelKey: const Key('tier-delete-cancel'),
      request: (api, token) => api.deletePriceTier(token, tier.id),
    );
    if (!mounted) return;
    _finish(result, l10n, deleting: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final existing = widget.tier;
    final catalog = ref.watch(catalogProvider).value;
    final taken = _taken(catalog);
    final tiers = catalog == null ? const <PriceTier>[] : _sortedTiers(catalog);
    final used =
        existing != null &&
        catalog != null &&
        _personCount(catalog, existing.id) > 0;
    final last = existing != null && catalog != null && tiers.length <= 1;
    final canSave = !_busy && _clean != null && !taken;
    return AlertDialog(
      title: Text(existing == null ? l10n.tierDialogNew : l10n.tierDialogEdit),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('tier-name'),
                controller: _name,
                maxLength: maxTierName,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: l10n.tierFieldName,
                  errorText: taken ? l10n.saveNameTaken : null,
                ),
              ),
              if (existing == null && tiers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.tierCopiesPrices(tiers.first.name),
                    key: const Key('tier-copy-hint'),
                  ),
                ),
              if (used || last)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    used
                        ? l10n.tierDeleteBlockedUsed
                        : l10n.tierDeleteBlockedLast,
                    key: const Key('tier-delete-hint'),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('tier-error'),
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
            key: const Key('tier-delete'),
            onPressed: _busy || used || last ? null : () => _delete(existing),
            child: Text(l10n.masterDelete),
          ),
        TextButton(
          key: const Key('tier-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          key: const Key('tier-save'),
          onPressed: canSave ? _save : null,
          child: Text(l10n.dialogSave),
        ),
      ],
    );
  }
}
