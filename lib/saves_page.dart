import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Cloud saves, read-only: every platform's saves under the account, newest
/// version first, and how much of the OpenPak allowance they use. Uploading,
/// deleting and connecting your own storage are deliberate work that belongs
/// on the website, so the screen points there instead of offering a tap.
class SavesPage extends StatefulWidget {
  const SavesPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<SavesPage> createState() => SavesPageState();
}

class SavesPageState extends State<SavesPage> {
  late Future<CloudSaves> _data;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() => _data = widget.api.saves());

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Saves')),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: FutureBuilder<CloudSaves>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final data = snap.data!;
            final usage = data.usage;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                SectionLabel('Storage'),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Your OpenPak allowance. Connect your own storage, and manage '
                    'versions, at openpak.org/account/saves.',
                    style: TextStyle(color: t.muted, fontSize: 13, height: 1.4),
                  ),
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
                      name: 'Version ${v.number}${v.pinned ? ' · pinned' : ''}',
                      pill: v.conflict ? 'conflict' : fmtBytes(v.size),
                      state: v.conflict ? RowState.warn : RowState.ok,
                      trailing: Text(
                        _when(v.savedAt ?? v.createdAt),
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
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

/// 2048 -> "2 kB", the same rounding the website shows.
String fmtBytes(int n) {
  if (n >= 1 << 30) return '${(n / (1 << 30)).toStringAsFixed(1)} GB';
  if (n >= 1 << 20) return '${(n / (1 << 20)).toStringAsFixed(1)} MB';
  if (n >= 1 << 10) return '${(n / (1 << 10)).round()} kB';
  return '$n B';
}
