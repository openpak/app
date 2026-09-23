import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'voice.dart';
import 'widgets.dart';

/// "splatoon-2" -> "Splatoon 2": the title server's name for a game, readable.
String gameName(String title) =>
    title.split('-').where((w) => w.isNotEmpty).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

/// Voice chat: the room of the game you are in, found by itself, or a room
/// joined by its code. Once joined, the page is the call: who is there, who
/// is talking, mute and leave.
class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.api, this.sessionFactory = VoiceSession.new});
  final OpenPakApi api;

  /// Tests replace the WebRTC session; the app never does.
  final VoiceSession Function(OpenPakApi api, String code) sessionFactory;

  @override
  State<VoicePage> createState() => _VoicePageState();
}

/// The theme's filled buttons span the width; beside something else they must not.
final _inline = FilledButton.styleFrom(minimumSize: const Size(0, 48));

class _VoicePageState extends State<VoicePage> {
  late Future<VoiceRoom?> _current;
  final _code = TextEditingController();
  VoiceSession? _session;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() {
    _current = widget.api.voiceCurrent();
  });

  @override
  void dispose() {
    _session?.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _join(String code) async {
    final s = widget.sessionFactory(widget.api, code);
    s.addListener(_changed);
    setState(() => _session = s);
    await s.start();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    final s = _session;
    setState(() => _session = null);
    s?.removeListener(_changed);
    await s?.leave();
    s?.dispose();
    _reload();
  }

  /// A typed code is checked first, so a typo is told as such rather than as
  /// a dropped connection.
  Future<void> _joinTyped() async {
    final code = _code.text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final room = await widget.api.voiceRoom(code);
      await _join(room.code);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room = await widget.api.createVoiceRoom();
      await _join(room.code);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = _session;
    return PopScope(
      // Leaving the page leaves the room: nothing keeps talking unseen.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _session?.leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.voiceTitle)),
        body: s == null ? _lobby(context) : _call(context, s),
      ),
    );
  }

  Widget _lobby(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _current.catchError((_) => null);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(l.voiceIntro, style: TextStyle(color: t.muted)),
          const SizedBox(height: 8),
          SectionLabel(l.voiceYourGame),
          FutureBuilder(
            future: _current,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(LoadFailure.reasonOf(l, snap.error), style: TextStyle(color: t.muted)),
                  ),
                );
              }
              final room = snap.data;
              if (room == null) {
                return Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.voiceNoGame, style: TextStyle(color: t.muted)),
                  ),
                );
              }
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text(l.voiceGameRoom(gameName(room.title), room.code)),
                      trailing: IconButton(
                        tooltip: l.voiceCopyCode,
                        icon: const Icon(Icons.copy),
                        onPressed: () => copyToClipboard(context, room.code, l.voiceCodeCopied),
                      ),
                    ),
                    for (final m in room.members)
                      ListTile(
                        dense: true,
                        leading: Avatar(name: m.displayName, online: m.inVoice),
                        title: Text(m.displayName),
                        subtitle: Text(m.inVoice ? l.voiceInVoice : l.voiceNotInVoice),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.headset_mic),
                        label: Text(l.voiceJoin),
                        onPressed: () => _join(room.code),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          SectionLabel(l.voiceByCode),
          Panel(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          decoration: const InputDecoration(hintText: 'ABC234'),
                          onSubmitted: (_) => _joinTyped(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(style: _inline, onPressed: _busy ? null : _joinTyped, child: Text(l.voiceJoinCode)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(l.voiceCodeHelp, style: TextStyle(color: t.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(l.voiceCreate),
                      onPressed: _busy ? null : _create,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _call(BuildContext context, VoiceSession s) {
    final t = tokensOf(context);
    final l = context.l10n;
    if (s.failure != null) {
      final why = switch (s.failure) {
        'microphone' => l.voiceFailedMicrophone,
        'voice_room_full' => l.errorVoiceRoomFull,
        'voice_room_unknown' => l.errorVoiceRoomUnknown,
        _ => l.voiceFailedDisconnected,
      };
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
        children: [
          Text(
            why,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted),
          ),
          const SizedBox(height: 16),
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  style: _inline,
                  onPressed: () {
                    final code = s.code;
                    _leave().then((_) => _join(code));
                  },
                  child: Text(l.voiceRejoin),
                ),
                OutlinedButton(onPressed: _leave, child: Text(l.voiceLeave)),
              ],
            ),
          ),
        ],
      );
    }
    final room = s.roster.room;
    if (!s.connected || room == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final peers = s.roster.peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final me = VoicePeer(id: s.roster.self ?? '', name: s.roster.selfName, muted: s.muted, speaking: s.speaking)
      ..linked = true;
    return Column(
      children: [
        ListTile(
          title: Text(room.isGame ? l.voiceGameRoom(gameName(room.title), room.code) : l.voiceCodeRoom(room.code)),
          subtitle: Text(l.voiceCount(peers.length + 1, room.maxMembers)),
          trailing: IconButton(
            tooltip: l.voiceCopyCode,
            icon: const Icon(Icons.copy),
            onPressed: () => copyToClipboard(context, room.code, l.voiceCodeCopied),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _PeerTile(peer: me, self: true),
              for (final p in peers) _PeerTile(peer: p),
              if (peers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.voiceAlone(room.code),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: l.voiceSpeaker,
                  isSelected: s.speaker,
                  icon: const Icon(Icons.volume_down),
                  selectedIcon: const Icon(Icons.volume_up),
                  onPressed: s.toggleSpeaker,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: s.muted ? FilledButton.styleFrom(backgroundColor: t.bad) : null,
                    icon: Icon(s.muted ? Icons.mic_off : Icons.mic),
                    label: Text(s.muted ? l.voiceUnmute : l.voiceMute),
                    onPressed: s.toggleMute,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(icon: const Icon(Icons.call_end), label: Text(l.voiceLeave), onPressed: _leave),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One person in the call. The ring around the avatar is the speaking light.
class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer, this.self = false});
  final VoicePeer peer;
  final bool self;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final talking = peer.speaking && !peer.muted;
    final status = peer.muted
        ? l.voiceMuted
        : talking
        ? l.voiceSpeaking
        : !peer.linked
        ? l.voiceConnecting
        : null;
    return ListTile(
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: talking ? t.ok : Colors.transparent, width: 3),
        ),
        child: Avatar(name: peer.name),
      ),
      title: Text(self ? l.voiceYou(peer.name) : peer.name),
      subtitle: status == null ? null : Text(status, style: TextStyle(color: talking ? t.ok : t.muted)),
      trailing: peer.muted ? Icon(Icons.mic_off, color: t.bad) : null,
    );
  }
}
