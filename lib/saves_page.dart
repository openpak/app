import 'package:flutter/material.dart';

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
  late Future<(CloudSaves, SavesStorage)> _data;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
    _data = Future.wait([widget.api.saves(), widget.api.savesStorage()])
        .then((r) => (r[0] as CloudSaves, r[1] as SavesStorage));
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

  Future<void> _connect(SavesStorage current) async {
    final cfg = await showDialog<StorageConfig>(
      context: context,
      builder: (_) => _StorageDialog(current: current),
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

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Saves')),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: FutureBuilder<(CloudSaves, SavesStorage)>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final (data, storage) = snap.data!;
            final usage = data.usage;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                SectionLabel('Storage'),
                if (storage.connected)
                  StateRow(
                    name: '${storage.bucket} · ${storage.endpoint}',
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
                        ? 'Your saves go to your own bucket. It is the only limit.'
                        : 'Your OpenPak allowance. Connect an S3-compatible bucket you own '
                            'for everything beyond it.',
                    style: TextStyle(color: t.muted, fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_outlined),
                      label: Text(storage.connected ? 'Edit storage' : 'Connect storage'),
                      onPressed: () => _connect(storage),
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
  const _StorageDialog({required this.current});
  final SavesStorage current;

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
  late bool _pathStyle = widget.current.connected ? widget.current.pathStyle : true;
  late bool _insecure = widget.current.insecure;

  @override
  void dispose() {
    for (final c in [_endpoint, _region, _bucket, _prefix, _access, _secret]) {
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
    final ready = _endpoint.text.trim().isNotEmpty &&
        _bucket.text.trim().isNotEmpty &&
        _access.text.trim().isNotEmpty &&
        (_secret.text.isNotEmpty || widget.current.connected);
    return AlertDialog(
      title: Text(widget.current.connected ? 'Edit storage' : 'Connect storage'),
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
                    StorageConfig(
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
