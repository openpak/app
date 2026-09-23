/// Voice chat: one room, talked to over WebRTC, phone to phone.
///
/// The server only says who is in the room and passes offers, answers and ICE
/// candidates along (website internal/voice); the audio goes straight between
/// the phones, or through the TURN relay it hands out. Every phone connects to
/// every other one (a full mesh), which is why a room holds eight.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api.dart';

/// Someone connected to the room.
class VoicePeer {
  VoicePeer({required this.id, required this.name, this.muted = false, this.speaking = false});
  final String id;
  final String name;
  bool muted;
  bool speaking;

  /// Whether the WebRTC link to them is up (always true for yourself).
  bool linked = false;

  factory VoicePeer.fromJson(Map<String, dynamic> j) => VoicePeer(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    muted: j['muted'] == true,
    speaking: j['speaking'] == true,
  );
}

/// The room as the server describes it, kept apart from WebRTC so the rules
/// can be tested without a microphone.
class VoiceRoster {
  String? self;
  String selfName = '';
  VoiceRoom? room;
  List<Map<String, dynamic>> iceServers = const [];
  final peers = <String, VoicePeer>{};

  /// Applies one server frame. Returns the peers the newcomer must offer to:
  /// on a welcome, everybody already there (existing peers only answer, so two
  /// phones never offer to each other at once); otherwise none.
  List<String> apply(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'welcome':
        self = m['self'] as String?;
        selfName = m['name'] as String? ?? '';
        room = VoiceRoom.fromJson(m['room'] as Map<String, dynamic>? ?? const {});
        iceServers = ((m['ice_servers'] as List?) ?? const []).cast<Map<String, dynamic>>();
        peers.clear();
        for (final p in (m['peers'] as List?) ?? const []) {
          final peer = VoicePeer.fromJson(p as Map<String, dynamic>);
          if (peer.id != self) peers[peer.id] = peer;
        }
        return peers.keys.toList();
      case 'join':
        final peer = VoicePeer.fromJson(m['peer'] as Map<String, dynamic>? ?? const {});
        if (peer.id.isNotEmpty && peer.id != self) peers[peer.id] = peer;
      case 'leave':
        peers.remove(m['id']);
      case 'state':
        final p = peers[m['id']];
        if (p != null) {
          p.muted = m['muted'] == true;
          p.speaking = m['speaking'] == true;
        }
    }
    return const [];
  }
}

/// Speaking, from the microphone's level: on above [on], off only after the
/// level has stayed below it for [hold], so the ring does not flicker between
/// words.
class SpeakingDetector {
  SpeakingDetector({this.on = 0.03, this.hold = const Duration(milliseconds: 700)});
  final double on;
  final Duration hold;
  bool speaking = false;
  DateTime? _lastLoud;

  /// Feeds one level (0..1); returns true when [speaking] changed.
  bool feed(double level, DateTime now) {
    if (level >= on) _lastLoud = now;
    final next = _lastLoud != null && now.difference(_lastLoud!) < hold;
    if (next == speaking) return false;
    speaking = next;
    return true;
  }
}

/// A live voice session. [start] asks for the microphone and joins; [leave]
/// ends everything. Listeners are told whenever anything on screen changes.
class VoiceSession extends ChangeNotifier {
  VoiceSession(this.api, this.code);
  final OpenPakApi api;
  final String code;

  final roster = VoiceRoster();
  final _detector = SpeakingDetector();
  bool muted = false;
  bool speaker = true;
  bool get speaking => _detector.speaking;

  /// Why the session ended when it was not [leave]: a server error code
  /// (voice_room_full, voice_room_unknown), 'disconnected', or 'microphone'.
  String? failure;
  bool connected = false;

  WebSocket? _ws;
  MediaStream? _local;
  final _pcs = <String, RTCPeerConnection>{};
  final _pending = <String, List<RTCIceCandidate>>{};
  Future<void> _queue = Future.value();
  Timer? _meter;
  bool _closed = false;

  Future<void> start() async {
    try {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': false,
      });
    } catch (_) {
      _fail('microphone');
      return;
    }
    await _route();
    try {
      _ws = await WebSocket.connect(
        api.voiceSocketUri(code).toString(),
        protocols: const ['openpak-voice'],
        headers: api.voiceHeaders,
      );
    } on WebSocketException catch (e) {
      // The upgrade was refused with a status: 404 unknown room, 409 full.
      _fail(
        e.message.contains('409')
            ? 'voice_room_full'
            : e.message.contains('404')
            ? 'voice_room_unknown'
            : 'disconnected',
      );
      return;
    } catch (_) {
      _fail('disconnected');
      return;
    }
    _ws!.listen(
      (raw) {
        if (raw is! String) return;
        final m = jsonDecode(raw) as Map<String, dynamic>;
        // Frames are handled strictly in order: an ICE candidate must not
        // overtake the offer it belongs to while that offer is still being applied.
        _queue = _queue.then((_) => _onFrame(m)).catchError((Object e) => debugPrint('voice: $e'));
      },
      onDone: () => _fail('disconnected'),
      onError: (_) => _fail('disconnected'),
      cancelOnError: true,
    );
    _meter = Timer.periodic(const Duration(milliseconds: 250), (_) => _measure());
  }

  Future<void> _route() async {
    try {
      await Helper.setSpeakerphoneOn(speaker);
    } catch (_) {
      // Desktop and tests have no earpiece to choose between.
    }
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await _route();
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    if (muted) _detector.speaking = false;
    _sendState();
    notifyListeners();
  }

  void _sendState() => _send({'type': 'state', 'muted': muted, 'speaking': speaking && !muted});

  void _send(Map<String, dynamic> m) {
    if (_ws?.readyState == WebSocket.open) _ws!.add(jsonEncode(m));
  }

  Future<void> _onFrame(Map<String, dynamic> m) async {
    if (_closed) return;
    switch (m['type']) {
      case 'error':
        _fail(m['code'] as String? ?? 'disconnected');
        return;
      case 'leave':
        final id = m['id'] as String?;
        await _pcs.remove(id)?.close();
        _pending.remove(id);
      case 'signal':
        await _onSignal(m['from'] as String? ?? '', m['data'] as Map<String, dynamic>? ?? const {});
        return;
    }
    final offerTo = roster.apply(m);
    if (m['type'] == 'welcome') {
      connected = true;
      _sendState();
    }
    notifyListeners();
    for (final id in offerTo) {
      final pc = await _peerConnection(id);
      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      _send({
        'type': 'signal',
        'to': id,
        'data': {'sdp': offer.toMap()},
      });
    }
  }

  Future<RTCPeerConnection> _peerConnection(String id) async {
    final existing = _pcs[id];
    if (existing != null) return existing;
    final pc = await createPeerConnection({'iceServers': roster.iceServers, 'sdpSemantics': 'unified-plan'});
    _pcs[id] = pc;
    final local = _local!;
    for (final t in local.getAudioTracks()) {
      await pc.addTrack(t, local);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _send({
          'type': 'signal',
          'to': id,
          'data': {'candidate': c.toMap()},
        });
      }
    };
    pc.onConnectionState = (s) {
      final p = roster.peers[id];
      if (p == null) return;
      p.linked = s == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      notifyListeners();
    };
    // Remote audio plays by itself on Android and iOS: no renderer needed.
    return pc;
  }

  Future<void> _onSignal(String from, Map<String, dynamic> data) async {
    if (!roster.peers.containsKey(from)) return;
    final sdp = data['sdp'];
    if (sdp is Map) {
      final pc = await _peerConnection(from);
      await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?));
      for (final c in _pending.remove(from) ?? const <RTCIceCandidate>[]) {
        await pc.addCandidate(c);
      }
      if (sdp['type'] == 'offer') {
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _send({
          'type': 'signal',
          'to': from,
          'data': {'sdp': answer.toMap()},
        });
      }
      return;
    }
    final cand = data['candidate'];
    if (cand is Map) {
      final c = RTCIceCandidate(
        cand['candidate'] as String?,
        cand['sdpMid'] as String?,
        (cand['sdpMLineIndex'] as num?)?.toInt(),
      );
      final pc = _pcs[from];
      if (pc != null && await pc.getRemoteDescription() != null) {
        await pc.addCandidate(c);
      } else {
        (_pending[from] ??= []).add(c);
      }
    }
  }

  /// Samples the microphone's level from any live link (WebRTC measures the
  /// source once for all of them) and tells the room when speaking changes.
  Future<void> _measure() async {
    if (muted || _pcs.isEmpty) return;
    try {
      final stats = await _pcs.values.first.getStats();
      for (final r in stats) {
        if (r.type == 'media-source' && r.values['kind'] == 'audio') {
          final level = (r.values['audioLevel'] as num?)?.toDouble() ?? 0;
          if (_detector.feed(level, DateTime.now())) {
            _sendState();
            notifyListeners();
          }
          return;
        }
      }
    } catch (_) {
      // A link closing under the sampler is not worth reporting.
    }
  }

  void _fail(String why) {
    if (_closed) return;
    failure = why;
    _teardown();
    notifyListeners();
  }

  /// Leaves the room and releases the microphone.
  Future<void> leave() async {
    if (_closed) return;
    _teardown();
    notifyListeners();
  }

  void _teardown() {
    _closed = true;
    connected = false;
    _meter?.cancel();
    for (final pc in _pcs.values) {
      pc.close();
    }
    _pcs.clear();
    for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      t.stop();
    }
    _local?.dispose();
    _local = null;
    _ws?.close();
    _ws = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
