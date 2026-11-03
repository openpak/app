import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'l10n.dart';
import 'open_url.dart';
import 'pakka_page.dart';
import 'theme.dart';
import 'widgets.dart';

const _supportUrl = 'https://github.com/openpak/.github/blob/main/SUPPORT.md';

/// A topic in the app's language; a topic this app does not know is shown as sent.
String supportCategoryLabel(AppLocalizations l, String c) => switch (c) {
  'account' => l.supportCatAccount,
  'network' => l.supportCatNetwork,
  'switch' => l.supportCatSwitch,
  'wiiu-3ds' => l.supportCatWiiu3ds,
  'emulator' => l.supportCatEmulator,
  'saves' => l.supportCatSaves,
  'app' => l.supportCatApp,
  'other' => l.supportCatOther,
  _ => c,
};

String _statusLabel(AppLocalizations l, String s) => switch (s) {
  'waiting' => l.supportStatusWaiting,
  'closed' => l.supportStatusClosed,
  _ => l.supportStatusOpen,
};

RowState _statusState(String s) => switch (s) {
  'waiting' => RowState.ok,
  'closed' => RowState.idle,
  _ => RowState.warn,
};

/// Picks one picture from the gallery for a ticket (the system picker, so no
/// storage permission); null when nothing was chosen or it is too big.
Future<TicketUpload?> _pickScreenshot(BuildContext context) async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > ticketAttachmentLimit) {
    if (context.mounted) showToast(context, context.l10n.supportTooLarge);
    return null;
  }
  return (bytes: bytes, name: file.name);
}

/// The website's Help page: your requests, a form for a new one, and the
/// assistant when this account may use it. Answers arrive here (and by push).
class SupportPage extends StatefulWidget {
  const SupportPage({super.key, required this.api, this.subject = '', this.category, this.message = ''});
  final OpenPakApi api;

  /// A link can start a request, as the website's "Report a problem" does:
  /// these only fill the form in.
  final String subject, message;
  final String? category;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  late Future<(TicketList, bool)> _data;
  late final _subject = TextEditingController(text: widget.subject);
  late final _message = TextEditingController(text: widget.message);
  String? _category;
  TicketUpload? _file;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _load() => setState(() {
    _data = () async {
      final list = await widget.api.tickets();
      // Fail closed: no state, no way in to Pakka.
      final pakka = await widget.api.pakkaState().then((s) => s.visible, onError: (_) => false);
      return (list, pakka);
    }();
  });

  Future<void> _send(TicketList list) async {
    final l = context.l10n;
    final subject = _subject.text.trim(), message = _message.text.trim();
    if (subject.isEmpty || message.isEmpty || _category == null) {
      showToast(context, l.supportInvalid);
      return;
    }
    setState(() => _sending = true);
    try {
      final t = await widget.api.openTicket(
        subject: subject,
        category: _category!,
        message: message,
        attachment: _file,
      );
      if (!mounted) return;
      showToast(context, l.supportOpened);
      _subject.clear();
      _message.clear();
      setState(() {
        _file = null;
        _category = null;
      });
      _load();
      await _openTicket(t);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.statusCode == 400 ? l.supportInvalid : apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openTicket(Ticket t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketPage(api: widget.api, ticket: t)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.supportTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => _load(),
        child: FutureBuilder<(TicketList, bool)>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final err = snap.error;
            if (err is ApiException && err.statusCode == 503) {
              return ListView(
                padding: pagePadding(context, top: 24),
                children: [Text(l.supportUnavailable, textAlign: TextAlign.center, style: TextStyle(color: t.muted))],
              );
            }
            if (err != null) return LoadFailure(err);
            final (list, pakka) = snap.data!;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pagePadding(context, top: 16, bottom: 32),
              children: [
                Text(l.supportSub, style: TextStyle(color: t.muted)),
                if (pakka) ...[
                  const SizedBox(height: 12),
                  Panel(
                    child: ListTile(
                      leading: const PakkaAvatar(size: 36),
                      title: Text(l.pakkaTitle),
                      subtitle: Text(l.supportPakkaCta),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PakkaPage(api: widget.api))),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SectionLabel(l.supportYours, trailing: list.tickets.isEmpty ? null : '${list.tickets.length}'),
                if (list.tickets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(l.supportEmpty, style: TextStyle(color: t.muted)),
                  )
                else
                  for (final tk in list.tickets)
                    StateRow(
                      name: tk.subject,
                      pill: _statusLabel(l, tk.status),
                      state: _statusState(tk.status),
                      onTap: () => _openTicket(tk),
                    ),
                const SizedBox(height: 20),
                SectionLabel(l.supportNew),
                Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l.supportNewSub, style: TextStyle(color: t.muted, fontSize: 13)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _subject,
                          maxLength: 200,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(labelText: l.supportSubject),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: list.categories.contains(_category) ? _category : null,
                          decoration: InputDecoration(labelText: l.supportTopic),
                          items: [
                            for (final c in list.categories)
                              DropdownMenuItem(value: c, child: Text(supportCategoryLabel(l, c))),
                          ],
                          onChanged: (v) => setState(() => _category = v),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _message,
                          maxLength: 20000,
                          minLines: 5,
                          maxLines: 12,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(labelText: l.supportMessage, alignLabelWithHint: true),
                        ),
                        if (list.attachments) ...[
                          const SizedBox(height: 8),
                          _AttachmentPicker(
                            file: _file,
                            onPick: () async {
                              final f = await _pickScreenshot(context);
                              if (f != null) setState(() => _file = f);
                            },
                            onClear: () => setState(() => _file = null),
                          ),
                          Text(l.supportAttachmentHint, style: TextStyle(color: t.muted, fontSize: 12)),
                        ],
                        const SizedBox(height: 8),
                        Text(l.supportNoEmail, style: TextStyle(color: t.muted, fontSize: 12)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _sending ? null : () => _send(list),
                          child: Text(l.supportSend),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => openExternalUrl(Uri.parse(_supportUrl)),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.supportMoreHelp),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The attach button, or the chosen file with a way to drop it.
class _AttachmentPicker extends StatelessWidget {
  const _AttachmentPicker({required this.file, required this.onPick, required this.onClear});
  final TicketUpload? file;
  final VoidCallback onPick, onClear;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (file == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.attach_file, size: 18),
          label: Text(l.supportAttach),
        ),
      );
    }
    return Row(
      children: [
        const Icon(Icons.image_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(file!.name, overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: l.supportAttachRemove, onPressed: onClear, icon: const Icon(Icons.close)),
      ],
    );
  }
}

/// One ticket: the thread, oldest first, and a reply box. A reply puts a
/// closed ticket back in the queue, as on the website.
class TicketPage extends StatefulWidget {
  const TicketPage({super.key, required this.api, required this.ticket});
  final OpenPakApi api;
  final Ticket ticket;

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  late Future<Ticket> _data;
  final _reply = TextEditingController();
  TicketUpload? _file;
  bool _sending = false;
  bool _files = true;
  Ticket? _loaded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _load() => setState(() {
    _data = widget.api.ticket(widget.ticket.id).then((t) => _loaded = t);
    // Whether this deployment keeps files comes with the list.
    widget.api.tickets().then((l) {
      if (mounted) setState(() => _files = l.attachments);
    }, onError: (_) {});
  });

  Future<void> _send() async {
    final l = context.l10n;
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.api.replyTicket(widget.ticket.id, text, attachment: _file);
      if (!mounted) return;
      showToast(context, l.supportReplied);
      _reply.clear();
      _file = null;
      _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.statusCode == 400 ? l.supportInvalid : apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static const _images = ['png', 'jpg', 'jpeg', 'gif', 'webp'];

  Future<void> _openAttachment(TicketAttachment a) async {
    final l = context.l10n;
    final Uint8List bytes;
    try {
      bytes = await widget.api.ticketAttachment(a.url);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.statusCode == 404 ? l.supportDownloadFailed : apiErrorText(l, e));
      return;
    }
    if (!mounted) return;
    Future<void> share() => SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/octet-stream')],
      fileNameOverrides: [a.name],
    ));
    final ext = a.name.contains('.') ? a.name.split('.').last.toLowerCase() : '';
    if (!_images.contains(ext)) return share();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.all(12),
        content: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, _, _) => Text(a.name)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(MaterialLocalizations.of(ctx).closeButtonLabel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              share();
            },
            child: Text(ctx.l10n.supportShareFile),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(widget.ticket.subject, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<Ticket>(
        future: _data,
        builder: (context, snap) {
          final tk = snap.data ?? _loaded;
          if (tk == null) {
            if (snap.hasError) return LoadFailure(snap.error);
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            edgeOffset: glassTop(context),
            onRefresh: () async => _load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pagePadding(context, top: 16, bottom: 32),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatePill(text: _statusLabel(l, tk.status), state: _statusState(tk.status)),
                    Text(
                      '#${tk.id} · ${supportCategoryLabel(l, tk.category)}',
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final m in tk.thread) ...[
                  _MessageCard(message: m, onAttachment: _openAttachment),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                SectionLabel(l.supportReply),
                if (tk.status == 'closed')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l.supportReopen, style: TextStyle(color: t.muted, fontSize: 13)),
                  ),
                Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _reply,
                          maxLength: 20000,
                          minLines: 3,
                          maxLines: 10,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(labelText: l.supportMessage, alignLabelWithHint: true),
                        ),
                        if (_files)
                          _AttachmentPicker(
                            file: _file,
                            onPick: () async {
                              final f = await _pickScreenshot(context);
                              if (f != null) setState(() => _file = f);
                            },
                            onClear: () => setState(() => _file = null),
                          ),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _sending ? null : _send, child: Text(l.supportReply)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.onAttachment});
  final TicketMessage message;
  final void Function(TicketAttachment) onAttachment;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final a = message.attachment;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  message.fromStaff ? l.supportStaff : l.supportYou,
                  style: TextStyle(
                    fontFamily: uiFont,
                    fontWeight: FontWeight.w800,
                    color: message.fromStaff ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                const SizedBox(width: 8),
                if (message.createdAt != null)
                  Flexible(
                    child: Text(
                      shortDateTime(l, message.createdAt!),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(message.body),
            if (a != null) ...[
              const SizedBox(height: 8),
              ActionChip(
                avatar: const Icon(Icons.attach_file, size: 16),
                label: Text(a.name, overflow: TextOverflow.ellipsis),
                onPressed: () => onAttachment(a),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
