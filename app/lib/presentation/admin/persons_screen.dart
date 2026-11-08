import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dto.dart';
import '../../domain/catalog.dart';
import '../../domain/master_data.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../providers.dart';
import 'active_segments_header.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'master_data_save.dart';

/// Persons of the catalog: create, edit, deactivate and reactivate.
class PersonsScreen extends ConsumerStatefulWidget {
  const PersonsScreen({super.key});

  @override
  ConsumerState<PersonsScreen> createState() => _PersonsScreenState();
}

class _PersonsScreenState extends ConsumerState<PersonsScreen> {
  bool _showActive = true;

  /// The session ended (server restart, expiry): back to the gate, which
  /// shows the PIN prompt. Already gone when the idle logout left the area.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Future<void> _open(Catalog catalog, Person? person) {
    return showDialog<void>(
      context: context,
      builder: (_) => AdminIdleGuard(
        child: PersonDialog(catalog: catalog, person: person),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(catalogProvider).value;
    final activeCount = catalog?.persons.where((p) => p.isActive).length ?? 0;
    final inactiveCount = (catalog?.persons.length ?? 0) - activeCount;
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.personsTitle)),
        body: catalog == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ActiveSegmentsHeader(
                    segmentsKey: const Key('persons-segments'),
                    newKey: const Key('person-new'),
                    newLabel: l10n.personsNew,
                    showActive: _showActive,
                    activeCount: activeCount,
                    inactiveCount: inactiveCount,
                    onChanged: (v) => setState(() => _showActive = v),
                    onNew: () => _open(catalog, null),
                  ),
                  Expanded(child: _list(l10n, catalog)),
                ],
              ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n, Catalog catalog) {
    final tokens = DesignTokens.of(context);
    final shown = [
      for (final p in catalog.allPersonsByName())
        if (p.isActive == _showActive) p,
    ];
    final sections = <(String, List<Person>)>[
      (
        l10n.personsSectionCollective,
        [
          for (final p in shown)
            if (!p.isHidden && p.isCollective) p,
        ],
      ),
      for (final tier in [
        ...catalog.tiers,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        (
          tier.name,
          [
            for (final p in shown)
              if (!p.isHidden && !p.isCollective && p.priceTierId == tier.id) p,
          ],
        ),
      (
        l10n.personsSectionHidden,
        [
          for (final p in shown)
            if (p.isHidden) p,
        ],
      ),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        for (final (title, members) in sections)
          if (members.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                title,
                style: TextStyle(color: tokens.muted, fontSize: 18),
              ),
            ),
            for (final p in members)
              ListTile(
                key: Key('person-${p.id}'),
                title: Text(p.name, style: const TextStyle(fontSize: 22)),
                onTap: () => _open(catalog, p),
              ),
          ],
      ],
    );
  }
}

/// Create ([person] null) or edit a person. Deactivating or reactivating is
/// saved at once with the current field values.
class PersonDialog extends ConsumerStatefulWidget {
  const PersonDialog({super.key, required this.catalog, this.person});

  final Catalog catalog;
  final Person? person;

  @override
  ConsumerState<PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends ConsumerState<PersonDialog> {
  late final TextEditingController _name;
  late String _tierId;
  late bool _collective;
  late bool _hidden;
  String? _error;
  bool _busy = false;

  List<PriceTier> get _tiers =>
      [...widget.catalog.tiers]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  void initState() {
    super.initState();
    final p = widget.person;
    _name = TextEditingController(text: p?.name ?? '');
    _tierId = p?.priceTierId ?? _tiers.first.id;
    _collective = p?.isCollective ?? false;
    _hidden = p?.isHidden ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _clean => cleanName(_name.text, maxPersonName);

  bool get _taken {
    final clean = _clean;
    return clean != null &&
        nameTaken(clean, [
          for (final p in widget.catalog.persons) (id: p.id, name: p.name),
        ], exceptId: widget.person?.id);
  }

  Future<void> _save({bool? isActive}) async {
    final name = _clean;
    if (name == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final existing = widget.person;
    final dto = PersonWriteDto(
      name: name,
      priceTierId: _tierId,
      isHidden: _hidden,
      isCollective: _collective,
      isActive: existing == null ? null : (isActive ?? existing.isActive),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await saveMasterData(ref, l10n, (api, token) async {
      if (existing == null) {
        await api.createPerson(token, dto);
      } else {
        await api.updatePerson(token, existing.id, dto);
      }
    });
    if (!mounted) return;
    switch (result) {
      case Saved():
        Navigator.of(context).pop();
      case SaveFailed(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
      case SaveSessionEnded():
        // The screen's session listener leaves the admin area.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final existing = widget.person;
    final taken = _taken;
    return AlertDialog(
      title: Text(
        existing == null ? l10n.personDialogNew : l10n.personDialogEdit,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('person-name'),
                controller: _name,
                maxLength: maxPersonName,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: l10n.personFieldName,
                  errorText: taken ? l10n.saveNameTaken : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.personFieldTier),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                key: const Key('person-tier'),
                showSelectedIcon: false,
                segments: [
                  for (final t in _tiers)
                    ButtonSegment(value: t.id, label: Text(t.name)),
                ],
                selected: {_tierId},
                onSelectionChanged: (s) => setState(() => _tierId = s.first),
              ),
              CheckboxListTile(
                key: const Key('person-collective'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _collective,
                onChanged: (v) => setState(() => _collective = v ?? false),
                title: Text(l10n.personCollective),
              ),
              CheckboxListTile(
                key: const Key('person-hidden'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _hidden,
                onChanged: (v) => setState(() => _hidden = v ?? false),
                title: Text(l10n.personHidden),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('person-error'),
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
            key: const Key('person-toggle-active'),
            onPressed: _busy || _clean == null || taken
                ? null
                : () => _save(isActive: !existing.isActive),
            child: Text(
              existing.isActive ? l10n.personDeactivate : l10n.personActivate,
            ),
          ),
        TextButton(
          key: const Key('person-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          key: const Key('person-save'),
          onPressed: _busy || _clean == null || taken ? null : _save,
          child: Text(l10n.dialogSave),
        ),
      ],
    );
  }
}
