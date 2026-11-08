import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dto.dart';
import '../../data/api/mappers.dart' show hexFromColor;
import '../../domain/catalog.dart';
import '../../domain/master_data.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'delete_confirm.dart';
import 'master_data_save.dart';

List<DrinkGroup> _sortedGroups(Catalog catalog) =>
    [...catalog.groups]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

int _drinkCount(Catalog catalog, String groupId) =>
    catalog.drinks.where((d) => d.groupId == groupId).length;

/// Drink groups: create, rename, recolour, delete and reorder.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  /// Optimistic order (all group ids) while a reorder request runs.
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

  Future<void> _open(DrinkGroup? group) {
    return showDialog<void>(
      context: context,
      builder: (_) => AdminIdleGuard(child: GroupDialog(group: group)),
    );
  }

  List<DrinkGroup> _ordered(Catalog catalog) {
    final groups = _sortedGroups(catalog);
    final pending = _pending;
    if (pending != null && pending.length == groups.length) {
      final byId = {for (final g in groups) g.id: g};
      if (pending.every(byId.containsKey)) {
        return [for (final id in pending) byId[id]!];
      }
    }
    return groups;
  }

  Future<void> _reorder(Catalog catalog, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final groups = _ordered(catalog);
    groups.insert(newIndex, groups.removeAt(oldIndex));
    final ids = [for (final g in groups) g.id];
    setState(() => _pending = ids);
    final result = await saveMasterData(
      ref,
      l10n,
      (api, token) => api.reorderGroups(token, ids),
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
        appBar: AppBar(title: Text(l10n.groupsTitle)),
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
                        key: const Key('group-new'),
                        onPressed: () => _open(null),
                        child: Text(l10n.groupsNew),
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
    final groups = _ordered(catalog);
    return ReorderableListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      buildDefaultDragHandles: false,
      onReorderItem: (o, n) => _reorder(catalog, o, n),
      children: [
        for (final (i, g) in groups.indexed)
          ListTile(
            key: Key('group-${g.id}'),
            leading: Container(
              key: Key('group-dot-${g.id}'),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color(g.color),
                shape: BoxShape.circle,
              ),
            ),
            title: Text(g.name, style: const TextStyle(fontSize: 22)),
            subtitle: Text(
              l10n.groupDrinkCount(_drinkCount(catalog, g.id)),
              style: TextStyle(color: tokens.muted, fontSize: 16),
            ),
            trailing: ReorderableDragStartListener(
              index: i,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.drag_handle,
                  key: Key('group-handle-${g.id}'),
                  size: 32,
                ),
              ),
            ),
            onTap: () => _open(g),
          ),
      ],
    );
  }
}

/// Create ([group] null) or edit a drink group: name and palette colour.
class GroupDialog extends ConsumerStatefulWidget {
  const GroupDialog({super.key, this.group});

  final DrinkGroup? group;

  @override
  ConsumerState<GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends ConsumerState<GroupDialog> {
  late final TextEditingController _name;
  late String _color;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _name = TextEditingController(text: g?.name ?? '');
    _color = g == null ? groupPalette.first : hexFromColor(g.color);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _clean => cleanName(_name.text, maxGroupName);

  /// The palette plus the stored colour when it is not part of it.
  List<String> get _swatches {
    final stored = widget.group == null
        ? null
        : hexFromColor(widget.group!.color);
    return [
      ...groupPalette,
      if (stored != null && !groupPalette.contains(stored)) stored,
    ];
  }

  bool _taken(Catalog? catalog) {
    final clean = _clean;
    return clean != null &&
        catalog != null &&
        nameTaken(clean, [
          for (final g in catalog.groups) (id: g.id, name: g.name),
        ], exceptId: widget.group?.id);
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
    final existing = widget.group;
    final dto = GroupWriteDto(name: name, color: _color);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await saveMasterData(ref, l10n, (api, token) async {
      if (existing == null) {
        await api.createGroup(token, dto);
      } else {
        await api.updateGroup(token, existing.id, dto);
      }
    });
    if (!mounted) return;
    _finish(result, l10n);
  }

  Future<void> _delete(DrinkGroup group) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await confirmAndDelete(
      context,
      ref,
      title: l10n.groupDeleteConfirm(group.name),
      confirmKey: const Key('group-delete-confirm'),
      cancelKey: const Key('group-delete-cancel'),
      request: (api, token) => api.deleteGroup(token, group.id),
    );
    if (!mounted) return;
    _finish(result, l10n, deleting: true);
  }

  Widget _swatch(String hex) {
    final selected = hex == _color;
    return GestureDetector(
      key: Key('group-swatch-$hex'),
      onTap: () => setState(() => _color = hex),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 24)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final existing = widget.group;
    final catalog = ref.watch(catalogProvider).value;
    final taken = _taken(catalog);
    final used =
        existing != null &&
        catalog != null &&
        _drinkCount(catalog, existing.id) > 0;
    final canSave = !_busy && _clean != null && !taken;
    return AlertDialog(
      title: Text(
        existing == null ? l10n.groupDialogNew : l10n.groupDialogEdit,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('group-name'),
                controller: _name,
                maxLength: maxGroupName,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: l10n.groupFieldName,
                  errorText: taken ? l10n.saveNameTaken : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.groupFieldColor),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final hex in _swatches) _swatch(hex)],
              ),
              if (used)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.groupDeleteBlocked,
                    key: const Key('group-delete-hint'),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('group-error'),
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
            key: const Key('group-delete'),
            onPressed: _busy || used ? null : () => _delete(existing),
            child: Text(l10n.masterDelete),
          ),
        TextButton(
          key: const Key('group-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          key: const Key('group-save'),
          onPressed: canSave ? _save : null,
          child: Text(l10n.dialogSave),
        ),
      ],
    );
  }
}
