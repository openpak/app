import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n.dart';
import 'open_url.dart';
import 'theme.dart';
import 'widgets.dart';

const _termsFallback = 'https://openpak.org/operators';

String _roleLabel(AppLocalizations l, String r) => switch (r) {
  'photon' => l.operatorRolePhoton,
  'turn' => l.operatorRoleTurn,
  'stun' => l.operatorRoleStun,
  'npln_relay' => l.operatorRoleNplnRelay,
  _ => r,
};

String _statusLabel(AppLocalizations l, String s) => switch (s) {
  'approved' => l.operatorStatusApproved,
  'rejected' => l.operatorStatusRejected,
  'info' => l.operatorStatusInfo,
  'waitlist' => l.operatorStatusWaitlist,
  _ => l.operatorStatusPending,
};

RowState _statusState(String s) => switch (s) {
  'approved' => RowState.ok,
  'rejected' => RowState.bad,
  _ => RowState.warn,
};

/// Running a region node, as /account/operator on the website: what is
/// needed, where nodes are wanted, your applications, and the form.
class OperatorPage extends StatefulWidget {
  const OperatorPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<OperatorPage> createState() => _OperatorPageState();
}

class _OperatorPageState extends State<OperatorPage> {
  late Future<OperatorInfo> _data;
  bool _waitlist = false; // the waitlist form instead of the application

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
    _data = widget.api.operatorInfo();
  });

  void _done(String message) {
    showToast(context, message);
    setState(() => _waitlist = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.operatorTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => _load(),
        child: FutureBuilder<OperatorInfo>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final err = snap.error;
            if (err is ApiException && err.statusCode == 503) {
              return ListView(
                padding: pagePadding(context, top: 24),
                children: [Text(l.operatorUnavailable, textAlign: TextAlign.center, style: TextStyle(color: t.muted))],
              );
            }
            if (err != null) return LoadFailure(err);
            final info = snap.data!;
            final terms = Uri.parse(info.termsUrl.isEmpty ? _termsFallback : info.termsUrl);
            final open = info.locations.isNotEmpty && !_waitlist;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pagePadding(context, top: 16, bottom: 32),
              children: [
                Text(l.operatorIntro, style: TextStyle(color: t.muted)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => openExternalUrl(terms),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l.operatorTermsLink),
                  ),
                ),
                if (info.requirements.isNotEmpty) ...[
                  SectionLabel(l.operatorReqTitle),
                  _Requirements(info: info),
                  const SizedBox(height: 20),
                ],
                if (info.applications.isNotEmpty) ...[
                  SectionLabel(l.operatorApps),
                  for (final a in info.applications) ...[
                    _ApplicationCard(api: widget.api, app: a, onReplied: () => _done(l.operatorDoneReplied)),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                ],
                if (!info.inReview) ...[
                  if (open) ...[
                    SectionLabel(l.operatorApply),
                    _ApplyForm(
                      api: widget.api,
                      info: info,
                      terms: terms,
                      onApplied: () => _done(l.operatorDoneApplied),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => setState(() => _waitlist = true), child: Text(l.operatorNotListed)),
                  ] else ...[
                    SectionLabel(l.operatorWaitlist),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(l.operatorNotWanted, style: TextStyle(color: t.muted, fontSize: 13)),
                    ),
                    _WaitlistForm(api: widget.api, onJoined: () => _done(l.operatorDoneWaitlist)),
                    if (info.locations.isNotEmpty)
                      TextButton(onPressed: () => setState(() => _waitlist = false), child: Text(l.operatorBack)),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Requirements extends StatelessWidget {
  const _Requirements({required this.info});
  final OperatorInfo info;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final r = info.requirements;
    String n(String k) => '${r[k] ?? 0}';
    Widget line(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(s),
    );
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line('${l.operatorReqNode}: ${n('node_cores')} ${l.operatorReqCores} · ${n('node_ram_gb')} GB RAM · ${n('node_disk_gb')} GB NVMe/SSD'),
            line('${l.operatorReqServer}: ${n('server_cores')} ${l.operatorReqCores} · ${n('server_ram_gb')} GB RAM · ${l.operatorReqIpv4} · ${n('server_bandwidth_mbps')} Mbps ${l.operatorReqSymmetric}'),
            line('${l.operatorReqAvailability}: ${n('availability_pct')} %'),
            Text(l.operatorReqNote, style: TextStyle(color: t.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatefulWidget {
  const _ApplicationCard({required this.api, required this.app, required this.onReplied});
  final OpenPakApi api;
  final OperatorApplication app;
  final VoidCallback onReplied;

  @override
  State<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<_ApplicationCard> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.operatorReply(widget.app.id, text);
      if (mounted) widget.onReplied();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final a = widget.app;
    final place = [a.city, a.country].where((e) => e.isNotEmpty).join(', ');
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(place, style: const TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                StatePill(text: _statusLabel(l, a.status), state: _statusState(a.status)),
              ],
            ),
            if (a.updatedAt != null)
              Text(shortDate(l, a.updatedAt!), style: TextStyle(color: t.muted, fontSize: 12)),
            if (a.adminNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '${a.status == 'rejected' ? l.operatorReason : l.operatorQuestion}: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: a.adminNote),
                ])),
              ),
            if (a.status == 'approved')
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.operatorApprovedNext)),
            if (a.status == 'info') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reply,
                maxLength: 2000,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l.operatorReplyLabel, alignLabelWithHint: true),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(onPressed: _busy ? null : _send, child: Text(l.operatorReplySend)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the server worded when it did not accept something, as a list.
class _Errors extends StatelessWidget {
  const _Errors(this.errors);
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.badWeak,
        border: Border.all(color: t.badLine),
        borderRadius: BorderRadius.circular(radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in errors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: t.bad)),
                  Expanded(child: Text(e)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ServerFields {
  final cores = TextEditingController(), ram = TextEditingController();
  final disk = TextEditingController(), bandwidth = TextEditingController();
  bool ssd = true, ipv6 = false;
  final roles = <String>{};

  void dispose() {
    for (final c in [cores, ram, disk, bandwidth]) {
      c.dispose();
    }
  }

  OperatorServer? toServer() {
    final c = int.tryParse(cores.text.trim()) ?? 0;
    if (c <= 0) return null; // a row without cores is skipped, as on the website
    return OperatorServer(
      cores: c,
      ramGb: int.tryParse(ram.text.trim()) ?? 0,
      diskGb: int.tryParse(disk.text.trim()) ?? 0,
      diskSsd: ssd,
      bandwidthMbps: int.tryParse(bandwidth.text.trim()) ?? 0,
      ipv6: ipv6,
      roles: roles.toList(),
    );
  }
}

class _ApplyForm extends StatefulWidget {
  const _ApplyForm({required this.api, required this.info, required this.terms, required this.onApplied});
  final OpenPakApi api;
  final OperatorInfo info;
  final Uri terms;
  final VoidCallback onApplied;

  @override
  State<_ApplyForm> createState() => _ApplyFormState();
}

class _ApplyFormState extends State<_ApplyForm> {
  final _city = TextEditingController(), _provider = TextEditingController();
  final _email = TextEditingController(), _notes = TextEditingController();
  final _servers = [_ServerFields()];
  String? _location;
  bool _terms = false, _busy = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    for (final c in [_city, _provider, _email, _notes]) {
      c.dispose();
    }
    for (final s in _servers) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _errors = const [];
    });
    try {
      await widget.api.operatorApply(
        location: _location ?? '',
        city: _city.text.trim(),
        provider: _provider.text.trim(),
        email: _email.text.trim(),
        notes: _notes.text.trim(),
        terms: _terms,
        servers: [for (final s in _servers) ?s.toServer()],
      );
      if (mounted) widget.onApplied();
    } on OperatorRejected catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final info = widget.info;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errors.isNotEmpty) _Errors(_errors),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _location,
              decoration: InputDecoration(labelText: l.operatorLocation, helperText: l.operatorLocationHint, helperMaxLines: 3),
              items: [
                for (final loc in info.locations)
                  DropdownMenuItem(
                    value: loc.code,
                    child: Text(
                      [loc.city, loc.country].where((e) => e.isNotEmpty).join(', ').ifEmpty(loc.code),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _location = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _city, maxLength: 64, decoration: InputDecoration(labelText: l.operatorCity)),
            TextField(controller: _provider, maxLength: 100, decoration: InputDecoration(labelText: l.operatorProvider)),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: l.operatorEmail),
            ),
            const SizedBox(height: 20),
            Text(l.operatorServers, style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(l.operatorServersHint, style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 8),
            for (var i = 0; i < _servers.length; i++) ...[
              _ServerCard(
                index: i,
                fields: _servers[i],
                roles: info.roles,
                digits: digits,
                onChanged: () => setState(() {}),
                onRemove: _servers.length > 1
                    ? () => setState(() => _servers.removeAt(i).dispose())
                    : null,
              ),
              const SizedBox(height: 10),
            ],
            if (_servers.length < info.maxServers)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _servers.add(_ServerFields())),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.operatorAddServer),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLength: 2000,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: l.operatorNotes, alignLabelWithHint: true),
            ),
            Row(
              children: [
                Checkbox(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false)),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${l.operatorAccept} '),
                      InkWell(
                        onTap: () => openExternalUrl(widget.terms),
                        child: Text(
                          l.operatorTermsLink,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy || !_terms || _location == null ? null : _submit,
              child: Text(l.operatorSubmit),
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.index,
    required this.fields,
    required this.roles,
    required this.digits,
    required this.onChanged,
    this.onRemove,
  });
  final int index;
  final _ServerFields fields;
  final List<String> roles;
  final List<TextInputFormatter> digits;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    Widget num(TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: digits,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${l.operatorServer} ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
              if (onRemove != null)
                IconButton(tooltip: l.operatorRemoveServer, onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
            ],
          ),
          num(fields.cores, l.operatorServerCores),
          num(fields.ram, l.operatorServerRam),
          num(fields.disk, l.operatorServerDisk),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: fields.ssd,
            title: Text(l.operatorServerSsd),
            onChanged: (v) {
              fields.ssd = v;
              onChanged();
            },
          ),
          num(fields.bandwidth, l.operatorServerBandwidth),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: fields.ipv6,
            title: Text(l.operatorServerIpv6),
            onChanged: (v) {
              fields.ipv6 = v;
              onChanged();
            },
          ),
          Text(l.operatorServerRoles, style: TextStyle(color: t.ink2, fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in roles)
                FilterChip(
                  label: Text(_roleLabel(l, r)),
                  selected: fields.roles.contains(r),
                  onSelected: (v) {
                    v ? fields.roles.add(r) : fields.roles.remove(r);
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaitlistForm extends StatefulWidget {
  const _WaitlistForm({required this.api, required this.onJoined});
  final OpenPakApi api;
  final VoidCallback onJoined;

  @override
  State<_WaitlistForm> createState() => _WaitlistFormState();
}

class _WaitlistFormState extends State<_WaitlistForm> {
  final _country = TextEditingController(), _city = TextEditingController(), _email = TextEditingController();
  bool _busy = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    for (final c in [_country, _city, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _errors = const [];
    });
    try {
      await widget.api.operatorWaitlist(
        country: _country.text.trim().toUpperCase(),
        city: _city.text.trim(),
        email: _email.text.trim(),
      );
      if (mounted) widget.onJoined();
    } on OperatorRejected catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errors.isNotEmpty) _Errors(_errors),
            TextField(
              controller: _country,
              maxLength: 2,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(labelText: l.operatorCountry),
            ),
            TextField(controller: _city, maxLength: 64, decoration: InputDecoration(labelText: l.operatorCity)),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: l.operatorEmail),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _join, child: Text(l.operatorWaitlistJoin)),
          ],
        ),
      ),
    );
  }
}
