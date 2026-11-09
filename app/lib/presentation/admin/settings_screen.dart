import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dto.dart';
import '../../domain/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../format.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';

final _log = Logger('admin');

/// Settings: mail recipients, the price tier that values shrinkage, and
/// re-sending the last settlement PDF. Each change is saved at once.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _address = TextEditingController();
  SettingsDto? _settings;
  String? _error;
  bool _unreachable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// The session ended: back to the gate, which shows the PIN prompt.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Future<void> _load() async {
    try {
      final settings = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.getSettings(token));
      if (mounted) setState(() => _settings = settings);
    } on AdminSessionEndedException {
      // The session listener returns to the PIN prompt.
    } on ApiException catch (e) {
      _log.info('Settings not loaded: ${e.message}');
      if (mounted) setState(() => _unreachable = true);
    }
  }

  /// Runs a write; null on success, otherwise the message to show.
  Future<String?> _write(
    AppLocalizations l10n,
    Future<void> Function(BarTabApi api, String token) request, {
    String? Function(ApiException e)? onError,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await ref.read(adminSessionProvider.notifier).run(request);
    } on AdminSessionEndedException {
      error = null;
    } on NetworkException catch (e) {
      _log.info('Settings write unreachable: ${e.message}');
      error = l10n.adminUnreachable;
    } on ApiException catch (e) {
      _log.info('Settings write failed: ${e.message}');
      error = onError?.call(e) ?? l10n.saveFailed;
    }
    if (mounted) setState(() => _busy = false);
    return error;
  }

  Future<void> _saveRecipients(List<String> next) async {
    final settings = _settings;
    if (settings == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final error = await _write(
      l10n,
      (api, token) => api.setRecipients(token, next),
      onError: (e) =>
          e is InvalidEmailException ? l10n.settingsInvalidEmail : null,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _address.clear();
    setState(() => _settings = settings.copyWith(recipients: next));
  }

  Future<void> _add() {
    final address = _address.text.trim();
    final current = _settings?.recipients ?? const <String>[];
    if (address.isEmpty) return Future.value();
    if (current.contains(address)) {
      _address.clear();
      return Future.value();
    }
    return _saveRecipients([...current, address]);
  }

  Future<void> _remove(String address) => _saveRecipients([
    for (final a in _settings!.recipients)
      if (a != address) a,
  ]);

  Future<void> _chooseTier(String tierId) async {
    final settings = _settings;
    if (settings == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final error = await _write(
      l10n,
      (api, token) => api.setValuationTier(token, tierId),
    );
    if (!mounted) return;
    setState(() {
      _error = error;
      if (error == null) {
        _settings = settings.copyWith(
          valuationTierId: tierId,
          effectiveValuationTierId: tierId,
        );
      }
    });
  }

  Future<void> _resend() async {
    final settings = _settings;
    final last = settings?.lastSettlement;
    if (settings == null || last == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    MailStatus? status;
    final error = await _write(l10n, (api, token) async {
      status = await api.resendSettlement(token);
    }, onError: (_) => l10n.settingsResendFailed);
    if (!mounted) return;
    setState(() {
      _error = error;
      final result = status;
      if (error == null && result != null) {
        _settings = settings.copyWith(
          lastSettlement: last.copyWith(mailStatus: result),
        );
      }
    });
  }

  String _statusText(AppLocalizations l10n, MailStatus status) =>
      switch (status) {
        MailStatus.sent => l10n.settingsMailSent,
        MailStatus.failed => l10n.settingsMailFailed,
        MailStatus.skipped => l10n.settingsMailSkipped,
        MailStatus.pending => l10n.settingsMailPending,
      };

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final settings = _settings;
    final catalog = ref.watch(catalogProvider).value;
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.settingsTitle)),
        body: _unreachable
            ? Center(child: Text(l10n.adminUnreachable))
            : settings == null || catalog == null
            ? const Center(child: CircularProgressIndicator())
            : _content(l10n, settings, catalog),
      ),
    );
  }

  Widget _content(
    AppLocalizations l10n,
    SettingsDto settings,
    Catalog catalog,
  ) {
    final tokens = DesignTokens.of(context);
    final tiers = [...catalog.tiers]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final tierId = tiers.any((t) => t.id == settings.effectiveValuationTierId)
        ? settings.effectiveValuationTierId
        : null;
    final last = settings.lastSettlement;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(l10n.settingsRecipients, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 8),
        for (final a in settings.recipients)
          ListTile(
            key: Key('recipient-$a'),
            title: Text(a, style: const TextStyle(fontSize: 20)),
            trailing: IconButton(
              key: Key('recipient-remove-$a'),
              tooltip: l10n.settingsRecipientRemove,
              icon: const Icon(Icons.delete_outline, size: 32),
              onPressed: _busy ? null : () => _remove(a),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('recipient-field'),
                controller: _address,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  labelText: l10n.settingsRecipientField,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('recipient-add'),
              onPressed: _busy ? null : _add,
              child: Text(l10n.settingsRecipientAdd),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const Key('settings-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 32),
        Row(
          children: [
            Text(
              l10n.settingsValuationTier,
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 16),
            DropdownButton<String>(
              key: const Key('valuation-tier'),
              value: tierId,
              items: [
                for (final t in tiers)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: _busy
                  ? null
                  : (id) {
                      if (id != null) _chooseTier(id);
                    },
            ),
          ],
        ),
        if (last != null) ...[
          const SizedBox(height: 32),
          Text(
            l10n.settingsLastSettlement,
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                formatBookingTime(last.closedAt),
                key: const Key('last-settlement-date'),
                style: TextStyle(color: tokens.muted, fontSize: 20),
              ),
              const SizedBox(width: 16),
              Text(
                _statusText(l10n, last.mailStatus),
                key: const Key('last-settlement-status'),
                style: const TextStyle(fontSize: 20),
              ),
              const Spacer(),
              OutlinedButton(
                key: const Key('settlement-resend'),
                onPressed: _busy ? null : _resend,
                child: Text(l10n.settingsResend),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
