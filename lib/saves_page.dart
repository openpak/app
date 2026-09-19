import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'theme.dart';
import 'titles_page.dart' show consoleAsset;
import 'widgets.dart';

/// Cloud saves, the website's page: the allowance, every game's saves with a version
/// dropdown (picking one makes it current), download and delete, then the player's own
/// storage.
class SavesPage extends StatefulWidget {
  const SavesPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<SavesPage> createState() => SavesPageState();
}

class SavesPageState extends State<SavesPage> {
  String _search = '';
  String? _console;
  late Future<(CloudSaves, SavesStorage, Map<String, bool>)> _data;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
    _data = Future.wait([
      widget.api.saves(),
      widget.api.savesStorage(),
      widget.api.storageKinds().catchError((_) => <String, bool>{'s3': true, 'webdav': true}),
    ]).then((r) => (r[0] as CloudSaves, r[1] as SavesStorage, r[2] as Map<String, bool>));
  });

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
    reload();
  }

  Future<void> _connect(SavesStorage current, String kind) async {
    final cfg = await showDialog<StorageConfig>(
      context: context,
      builder: (_) => _StorageDialog(current: current, kind: kind),
    );
    if (cfg == null) return;
    await _act(() async {
      final warning = await widget.api.connectStorage(cfg);
      if (warning != null && mounted) showToast(context, warning);
    }, 'Storage connected. New saves go to your bucket.');
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      ) ??
      false;

  /// The consent page opens in the browser; the website's callback finishes the connection
  /// for this account, so coming back here and pulling to refresh is all that is left.
  Future<void> _connectCloud(String provider) async {
    try {
      final url = await widget.api.storageOAuthUrl(provider);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) showToast(context, 'Could not open the browser.');
        return;
      }
      if (mounted) {
        showToast(context, 'Finish in the browser, then pull to refresh here.');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _delete(SaveVersion v) async {
    if (await _confirm('Delete this version?', 'Its bytes are removed from storage.')) {
      await _act(() => widget.api.deleteSave(v.id), 'Version deleted.');
    }
  }

  /// The bytes go to the share sheet, which saves them to Files, Drive or anywhere else.
  Future<void> _download(SaveVersion v) async {
    try {
      final bytes = await widget.api.downloadSave(v.id);
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/octet-stream')],
        fileNameOverrides: ['save-${v.id}.bin'],
      ));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Saves')),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: FutureBuilder<(CloudSaves, SavesStorage, Map<String, bool>)>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final (data, storage, kinds) = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // The website's order: what is used, the saves themselves, then where they go.
                _head('Storage', storage.connected
                    ? 'Your saves go to your own storage. Your bucket is the only limit.'
                    : 'Your OpenPak allowance. When it is full, uploads are refused until you '
                        'connect your own storage below.'),
                _usage(data.usage, storage),
                const SizedBox(height: 28),
                _head('Saves', 'Pick a version to make it the current one; the older one is kept.'),
                _list(data.saves),
                const SizedBox(height: 28),
                _head('Your own storage', 'Saves go straight there; OpenPak keeps only the index. '
                    'The secret is tested once and never shown again.'),
                ..._storage(storage, data.usage, kinds),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                  child: Text(
                    'Console backups have several parts and cannot be downloaded here yet.',
                    style: TextStyle(color: t.muted, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The website's section head: a heading and one muted line under it.
  Widget _head(String title, String sub) {
    final t = tokensOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(color: t.muted, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  Widget _usage(SavesUsage usage, SavesStorage storage) {
    if (storage.connected) {
      return StateRow(name: storage.name, pill: 'connected', state: RowState.ok);
    }
    final pct = usage.allowance > 0 ? usage.allowanceUsed * 100 ~/ usage.allowance : 0;
    final warn = pct >= 90;
    final t = tokensOf(context);
    return Column(
      children: [
        StateRow(
          name: '${fmtBytes(usage.allowanceUsed)} / ${fmtBytes(usage.allowance)}',
          pill: '$pct%',
          state: warn ? RowState.warn : RowState.ok,
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 6,
            color: warn ? t.warn : t.ok,
            backgroundColor: t.paper2,
          ),
        ),
      ],
    );
  }

  /// Search and console filter, then one card holding a row per game, as on the website.
  Widget _list(List<CloudSave> saves) {
    final t = tokensOf(context);
    final withVersions = saves.where((s) => s.versions.isNotEmpty).toList();
    if (withVersions.isEmpty) {
      return Panel(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No saves yet. An emulator pushes one when you quit a game; a console backs up '
            'from its Save Data Cloud screen.',
            style: TextStyle(color: t.ink2, height: 1.5),
          ),
        ),
      );
    }
    final consoles = withVersions.map((s) => platformConsole(s.platform)).toSet().toList()..sort();
    final q = _search.trim().toLowerCase();
    final shown = withVersions
        .where((s) => (q.isEmpty || s.name.toLowerCase().contains(q)) &&
            (_console == null || platformConsole(s.platform) == _console))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search by name',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _console,
          isExpanded: true,
          decoration: const InputDecoration(hintText: 'Console', isDense: true),
          items: [
            const DropdownMenuItem(value: null, child: Text('All consoles')),
            ...consoles.map((c) => DropdownMenuItem(value: c, child: Text(c))),
          ],
          onChanged: (v) => setState(() => _console = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text('Showing ${shown.length} / ${withVersions.length}',
              style: TextStyle(color: t.muted, fontSize: 13)),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No saves match.', style: TextStyle(color: t.muted))),
          )
        else
          Panel(
            child: Column(
              children: [
                for (final (i, s) in shown.indexed) ...[
                  if (i > 0) Divider(height: 1, color: t.line),
                  _SaveRow(
                    key: ObjectKey(s), // a reload resets the dropdown to the current version
                    save: s,
                    api: widget.api,
                    onRestore: (id) => _act(() => widget.api.restoreSave(id),
                        'Restored. That version is the current one now.'),
                    onDownload: _download,
                    onDelete: _delete,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _storage(SavesStorage storage, SavesUsage usage, Map<String, bool> kinds) {
    final t = tokensOf(context);
    Widget hint(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(s, style: TextStyle(color: t.muted, fontSize: 13, height: 1.4)),
        );
    return [
      if (storage.connected)
        StateRow(
          name: storage.name,
          pill: switch (storage.lastTestOk) {
            true => 'tested',
            false => 'not answering',
            null => 'not tested',
          },
          state: switch (storage.lastTestOk) {
            true => RowState.ok,
            false => RowState.bad,
            null => RowState.idle,
          },
        ),
      if (storage.lastError != null) hint(storage.lastError!),
      if (storage.moveState != null) hint('Move: ${storage.moveState}'),
      if (storage.connected) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (usage.allowanceUsed > 0)
              FilledButton.icon(
                icon: const Icon(Icons.drive_file_move_outline),
                label: Text('Move ${fmtBytes(usage.allowanceUsed)} here'),
                onPressed: () => _act(widget.api.moveSaves,
                    'Moving your saves. Pull to refresh in a moment.'),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(foregroundColor: t.bad),
              onPressed: () async {
                if (await _confirm(
                  'Disconnect storage?',
                  'Versions stored there stay listed but cannot be read until it is connected again.',
                )) {
                  await _act(widget.api.disconnectStorage, 'Storage disconnected.');
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
      // One tap, nothing to type: the clouds come first when the deployment
      // offers them. Running your own storage is the advanced case below.
      if (kinds['gdrive'] == true || kinds['onedrive'] == true) ...[
        hint('Google Drive or OneDrive: sign in once and saves go to a folder there.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (kinds['gdrive'] == true)
              OutlinedButton.icon(
                icon: const Icon(Icons.add_to_drive),
                label: const Text('Google Drive'),
                onPressed: () => _connectCloud('gdrive'),
              ),
            if (kinds['onedrive'] == true)
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('OneDrive'),
                onPressed: () => _connectCloud('onedrive'),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Advanced: your own bucket or server',
            style: TextStyle(color: t.ink2, fontSize: 14)),
        subtitle: Text(
          'For people who run their own storage. Everyone else needs none of this.',
          style: TextStyle(color: t.muted, fontSize: 12),
        ),
        initiallyExpanded: storage.connected && (storage.kind == 's3' || storage.kind == 'webdav'),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.storage_outlined),
                label: Text(storage.connected && storage.kind == 's3' ? 'Edit bucket' : 'S3 bucket'),
                onPressed: () => _connect(storage, 's3'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.dns_outlined),
                label: Text(storage.connected && storage.kind == 'webdav' ? 'Edit WebDAV' : 'WebDAV'),
                onPressed: () => _connect(storage, 'webdav'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    ];
  }
}

/// One game, the website's row: its icon (or the console's mark), the name, the console
/// logo with a conflict badge, then the version dropdown with download and delete. Picking
/// a version restores it, so the buttons always act on the current one.
class _SaveRow extends StatelessWidget {
  const _SaveRow({
    super.key,
    required this.save,
    required this.api,
    required this.onRestore,
    required this.onDownload,
    required this.onDelete,
  });
  final CloudSave save;
  final OpenPakApi api;
  final ValueChanged<int> onRestore;
  final ValueChanged<SaveVersion> onDownload;
  final ValueChanged<SaveVersion> onDelete;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final brightness = Theme.of(context).brightness;
    final console = platformConsole(save.platform);
    final cur = save.versions.first;
    final conflict = save.versions.any((v) => v.conflict);
    Widget mark(double w, double h) => SvgPicture.asset(
          'assets/consoles/${consoleAsset(console, brightness)}.svg',
          width: w,
          height: h,
          semanticsLabel: console,
        );
    final box = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.paper2, borderRadius: BorderRadius.circular(8)),
      child: mark(36, 24),
    );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              if (save.icon != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    api.absolute(save.icon!),
                    width: 48,
                    height: 48,
                    errorBuilder: (_, _, _) => box,
                  ),
                )
              else
                box,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(save.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        mark(24, 16),
                        if (conflict) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.warnWeak,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: t.warnLine),
                            ),
                            child: Text('Conflict',
                                style: TextStyle(color: t.warn, fontSize: 11.5, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: cur.id,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  style: TextStyle(color: t.ink2, fontSize: 13),
                  items: [
                    for (final v in save.versions)
                      DropdownMenuItem(
                        value: v.id,
                        child: Text(_versionLabel(v), overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null && id != cur.id) onRestore(id);
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download',
                onPressed: cur.parts == 1 ? () => onDownload(cur) : null,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: t.bad),
                tooltip: 'Delete',
                onPressed: () => onDelete(cur),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A version as the website's dropdown words it.
String _versionLabel(SaveVersion v) =>
    'Version ${v.number} · ${_when(v.savedAt ?? v.createdAt)} · ${fmtBytes(v.size)}'
    '${v.device != null ? ' · ${v.device}' : ''}'
    '${v.backend != 'local' ? ' · your storage' : ''}'
    '${v.conflict ? ' · Conflict' : ''}';

/// The console behind a saves platform, for the logo and the filter: the emulators' names
/// and the console's own. Same mapping as the website's platformConsole.
String platformConsole(String p) => switch (p.toLowerCase()) {
  'citron' || 'switch' => 'Switch',
  'wii' => 'Wii',
  'ds' => 'DS',
  _ => p,
};

String _when(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// The connect form. The secret is never shown back; empty keeps the stored one
/// when the access key is unchanged.
class _StorageDialog extends StatefulWidget {
  const _StorageDialog({required this.current, required this.kind});
  final SavesStorage current;
  final String kind; // s3 | webdav

  @override
  State<_StorageDialog> createState() => _StorageDialogState();
}

class _StorageDialogState extends State<_StorageDialog> {
  late final _endpoint = TextEditingController(text: widget.current.endpoint ?? '');
  late final _region = TextEditingController(text: widget.current.region ?? '');
  late final _bucket = TextEditingController(text: widget.current.bucket ?? '');
  late final _prefix = TextEditingController(text: widget.current.prefix ?? '');
  late final _access = TextEditingController(text: widget.current.accessKey ?? '');
  final _secret = TextEditingController();
  late final _url = TextEditingController(text: widget.current.url ?? '');
  late final _user = TextEditingController(text: widget.current.username ?? '');
  final _pass = TextEditingController();
  bool get _editing => widget.current.connected && widget.current.kind == widget.kind;
  late bool _pathStyle = _editing ? widget.current.pathStyle : true;
  late bool _insecure = widget.current.insecure;

  @override
  void dispose() {
    for (final c in [_endpoint, _region, _bucket, _prefix, _access, _secret, _url, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool secret = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (widget.kind == 'webdav') {
      final ready = _url.text.trim().isNotEmpty &&
          _user.text.trim().isNotEmpty &&
          (_pass.text.isNotEmpty || _editing);
      return AlertDialog(
        title: Text(_editing ? 'Edit WebDAV' : 'Connect WebDAV'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_url, 'WebDAV URL', hint: 'https://cloud.example.org/remote.php/dav/files/me/OpenPak'),
              _field(_user, 'Username'),
              _field(_pass, 'Password', secret: true),
              Text(
                'Nextcloud shows the URL under Settings › Files; add a folder for OpenPak at '
                'the end. Use an app password. The share is tested before it is saved.',
                style: TextStyle(color: t.muted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: ready
                ? () => Navigator.pop(
                      context,
                      StorageConfig.webdav(
                        url: _url.text.trim(),
                        username: _user.text.trim(),
                        password: _pass.text,
                      ),
                    )
                : null,
            child: const Text('Test and save'),
          ),
        ],
      );
    }
    final ready = _endpoint.text.trim().isNotEmpty &&
        _bucket.text.trim().isNotEmpty &&
        _access.text.trim().isNotEmpty &&
        (_secret.text.isNotEmpty || _editing);
    return AlertDialog(
      title: Text(_editing ? 'Edit bucket' : 'Connect a bucket'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_endpoint, 'Endpoint', hint: 's3.eu-west-1.amazonaws.com'),
            _field(_region, 'Region', hint: 'auto'),
            _field(_bucket, 'Bucket'),
            _field(_prefix, 'Folder (optional)', hint: 'openpak'),
            _field(_access, 'Access key'),
            _field(_secret, 'Secret key', secret: true),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _pathStyle,
              onChanged: (v) => setState(() => _pathStyle = v ?? true),
              title: const Text('Path-style addressing (most providers other than Amazon)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _insecure,
              onChanged: (v) => setState(() => _insecure = v ?? false),
              title: const Text('Plain HTTP (a box on your own network only)'),
            ),
            Text(
              'R2: <account>.r2.cloudflarestorage.com, region auto. '
              'B2: s3.<region>.backblazeb2.com. The bucket is tested before it is saved.',
              style: TextStyle(color: t.muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: ready
              ? () => Navigator.pop(
                    context,
                    StorageConfig.s3(
                      endpoint: _endpoint.text.trim().replaceFirst(RegExp(r'^https?://'), ''),
                      region: _region.text.trim(),
                      bucket: _bucket.text.trim(),
                      prefix: _prefix.text.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
                      accessKey: _access.text.trim(),
                      secretKey: _secret.text,
                      pathStyle: _pathStyle,
                      insecure: _insecure,
                    ),
                  )
              : null,
          child: const Text('Test and save'),
        ),
      ],
    );
  }
}

/// 2048 -> "2 kB", the same rounding the website shows.
String fmtBytes(int n) {
  if (n >= 1 << 30) return '${(n / (1 << 30)).toStringAsFixed(1)} GB';
  if (n >= 1 << 20) return '${(n / (1 << 20)).toStringAsFixed(1)} MB';
  if (n >= 1 << 10) return '${(n / (1 << 10)).round()} kB';
  return '$n B';
}
