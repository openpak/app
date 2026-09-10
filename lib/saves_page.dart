import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Cloud saves: every platform's saves under the account, newest version
/// first, the storage they use, and the player's own storage. Versions are
/// read-only here (restore, download and delete are deliberate work that
/// belongs on the website); storage can be connected, moved into and
/// disconnected, because those are settings rather than data.
class SavesPage extends StatefulWidget {
  const SavesPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<SavesPage> createState() => SavesPageState();
}

class SavesPageState extends State<SavesPage> {
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
            final usage = data.usage;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                SectionLabel('Storage'),
                if (storage.connected)
                  StateRow(
                    name: storage.name,
                    pill: storage.lastTestOk == false ? 'not answering' : 'connected',
                    state: storage.lastTestOk == false ? RowState.bad : RowState.ok,
                  )
                else
                  StateRow(
                    name: '${fmtBytes(usage.allowanceUsed)} of ${fmtBytes(usage.allowance)}',
                    pill: usage.allowance > 0
                        ? '${(usage.allowanceUsed * 100 ~/ usage.allowance)}%'
                        : '—',
                    state: usage.allowance > 0 &&
                            usage.allowanceUsed * 10 >= usage.allowance * 9
                        ? RowState.warn
                        : RowState.ok,
                  ),
                if (storage.lastError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(storage.lastError!,
                        style: TextStyle(color: t.muted, fontSize: 13, height: 1.4)),
                  ),
                if (storage.moveState != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text('Move: ${storage.moveState}',
                        style: TextStyle(color: t.muted, fontSize: 13, height: 1.4)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    storage.connected
                        ? 'Your saves go to your own storage. It is the only limit.'
                        : 'Your OpenPak allowance. Connect storage you own for everything '
                            'beyond it: a bucket, a WebDAV share, Google Drive or OneDrive.',
                    style: TextStyle(color: t.muted, fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 8),
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
                    if (storage.connected && usage.allowanceUsed > 0)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: Text('Move ${fmtBytes(usage.allowanceUsed)} here'),
                        onPressed: () => _act(widget.api.moveSaves,
                            'Moving your saves. Pull to refresh in a moment.'),
                      ),
                    if (storage.connected)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
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
                if (data.saves.isEmpty)
                  Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No saves yet. An emulator pushes one when you quit a '
                        'game; a console backs up from its Save Data Cloud screen.',
                        style: TextStyle(color: t.ink2, height: 1.5),
                      ),
                    ),
                  ),
                for (final save in data.saves) ...[
                  SectionLabel(
                    '${save.platform} · ${save.titleId}',
                    trailing: save.versions.length == 1
                        ? '1 version'
                        : '${save.versions.length} versions',
                  ),
                  for (final v in save.versions)
                    StateRow(
                      name: 'Version ${v.number}${v.pinned ? ' · pinned' : ''}'
                          '${v.backend != 'local' ? ' · your storage' : ''}',
                      pill: v.conflict ? 'conflict' : fmtBytes(v.size),
                      state: v.conflict ? RowState.warn : RowState.ok,
                      trailing: Text(
                        _when(v.savedAt ?? v.createdAt),
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Restore, download and delete versions at openpak.org/account/saves.',
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

  static String _when(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
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
