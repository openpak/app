import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n.dart';
import 'parental_console_page.dart';
import 'parental_lock.dart';
import 'theme.dart';
import 'widgets.dart';

/// Parental controls, parent side. Nintendo's own parent surface is a separate
/// smartphone app; ours is this screen. The console's half is local to it — the
/// PIN, the limits and the alarm all live on the console — so what happens here
/// is pairing, reading what a paired console holds and setting what it will
/// fetch next. It opens only behind the
/// phone's own unlock (parental_lock.dart).
class ParentalControlsPage extends StatelessWidget {
  const ParentalControlsPage({super.key, required this.api, this.lock});
  final OpenPakApi api;
  final ParentalLock? lock;

  @override
  Widget build(BuildContext context) =>
      ParentalLockGate(api: api, lock: lock, child: _ConsoleList(api: api, lock: lock));
}

class _ConsoleList extends StatefulWidget {
  const _ConsoleList({required this.api, this.lock});
  final OpenPakApi api;
  final ParentalLock? lock;

  @override
  State<_ConsoleList> createState() => _ConsoleListState();
}

class _ConsoleListState extends State<_ConsoleList> {
  late Future<List<ParentalDevice>> _devices;
  bool _pairing = false;

  /// The paired consoles at the last load; null before the first, so the
  /// consoles already there when the screen opens are not offered a name.
  Set<String>? _known;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final next = widget.api.parentalDevices();
    // A block, not an arrow: an arrow would hand setState the Future it assigns.
    setState(() {
      _devices = next;
    });
    next.then(_offerName, onError: (Object _) {});
  }

  /// A console that has just paired, and has no name of the parent's, is
  /// offered one: once, as it first appears.
  void _offerName(List<ParentalDevice> devices) {
    final known = _known;
    final paired = devices.where((d) => d.paired);
    _known = {for (final d in paired) d.moonId};
    if (known == null || !mounted) return;
    final fresh = paired.where((d) => !d.named && !known.contains(d.moonId)).firstOrNull;
    if (fresh == null) return;
    final l = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.parentalNameOffer),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l.parentalRename,
          onPressed: () async {
            if (!mounted) return;
            if (await renameConsole(context, widget.api, fresh) != null && mounted) _reload();
          },
        ),
      ),
    );
  }

  Future<void> _pair() async {
    final l = context.l10n;
    setState(() => _pairing = true);
    try {
      await widget.api.parentalPair();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
    _reload();
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    showToast(context, context.l10n.parentalCodeCopied);
  }

  // Reloaded on the way back: the console may have synced, or unlinked.
  Future<void> _open(ParentalDevice d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ParentalConsolePage(api: widget.api, device: d, lock: widget.lock)),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.parentalTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ParentalDevice>>(
          future: _devices,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final devices = snap.data ?? const <ParentalDevice>[];
            final waiting = devices.where((d) => d.waiting).toList(growable: false);
            final paired = devices.where((d) => d.paired).toList(growable: false);
            return ListView(
              padding: pagePadding(context),
              children: [
                Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.parentalHowTo, style: TextStyle(color: t.muted)),
                  ),
                ),
                const SizedBox(height: 16),
                // The code is the whole screen while one is live: it exists to
                // be read off a phone and typed into a console.
                if (waiting.isNotEmpty) ...[
                  SectionLabel(l.parentalCodeLabel),
                  ...waiting.map(
                    (d) => Panel(
                      child: ListTile(
                        title: Text(
                          d.pairingCode,
                          style: const TextStyle(
                            fontSize: 30,
                            fontFamily: 'monospace',
                            letterSpacing: 6,
                          ),
                        ),
                        subtitle: Text(l.parentalCodeValid, style: TextStyle(color: t.muted)),
                        trailing: IconButton(
                          icon: const Icon(Icons.content_copy),
                          tooltip: l.parentalCodeCopy,
                          onPressed: () => _copy(d.pairingCode),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SectionLabel(l.parentalConsoles, trailing: '${paired.length}'),
                if (paired.isEmpty)
                  Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.parentalNoConsoles, style: TextStyle(color: t.muted)),
                    ),
                  ),
                // A console that has claimed a code; its row opens what it
                // holds, and from there what can be changed.
                ...paired.map(
                  (d) => StateRow(
                    name: d.nickname.isEmpty ? l.parentalConsole : d.nickname,
                    // A server that does not say whether the console is up to
                    // date gets the older pill rather than a guess.
                    pill: switch (d.synced) {
                      true => l.parentalUpToDate,
                      false => l.parentalWaitingForConsole,
                      null => d.hasSetting ? l.parentalManaged : l.parentalNoLimits,
                    },
                    state: switch (d.synced) {
                      true => RowState.ok,
                      false => RowState.warn,
                      null => d.hasSetting ? RowState.ok : RowState.idle,
                    },
                    leading: const Icon(Icons.videogame_asset_outlined, size: 28),
                    onTap: () => _open(d),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _pairing ? null : _pair,
                  icon: const Icon(Icons.add),
                  label: Text(l.parentalPairConsole),
                ),
                const SizedBox(height: 16),
                Text(l.parentalOnConsoleNote, style: TextStyle(color: t.muted, fontSize: 13)),
              ],
            );
          },
        ),
      ),
    );
  }
}
