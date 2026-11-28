import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/call_models.dart';

class CallRoomPage extends StatefulWidget {
  const CallRoomPage({super.key, required this.joinResult});

  final CallJoinResultDto joinResult;

  @override
  State<CallRoomPage> createState() => _CallRoomPageState();
}

class _CallRoomPageState extends State<CallRoomPage> {
  Room? _room;
  bool _muted = false;
  bool _cameraOff = false;
  bool _screenSharing = false;
  String _status = '正在连接...';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    await [Permission.camera, Permission.microphone].request();

    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    room.addListener(_onRoomChanged);

    final policy = widget.joinResult.iceTransportPolicy == 'relay'
        ? 'relay'
        : 'all';

    await room.connect(
      widget.joinResult.rtcUrl,
      widget.joinResult.token,
      fastConnectOptions: FastConnectOptions(
        microphone: const TrackOption(enabled: true),
        camera: TrackOption(enabled: widget.joinResult.mediaType == 2),
      ),
    );

    if (!mounted) {
      await room.dispose();
      return;
    }
    setState(() {
      _room = room;
      _status = '通话中 (${policy.toUpperCase()})';
    });
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final room = _room;
    if (room == null) return;
    _muted = !_muted;
    await room.localParticipant?.setMicrophoneEnabled(!_muted);
    setState(() {});
  }

  Future<void> _toggleCamera() async {
    final room = _room;
    if (room == null) return;
    _cameraOff = !_cameraOff;
    await room.localParticipant?.setCameraEnabled(!_cameraOff);
    setState(() {});
  }

  Future<void> _toggleScreenShare() async {
    final room = _room;
    if (room == null) return;
    _screenSharing = !_screenSharing;
    await room.localParticipant?.setScreenShareEnabled(_screenSharing);
    setState(() {});
  }

  Future<void> _hangup() async {
    await _room?.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _room?.removeListener(_onRoomChanged);
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remoteParticipants = _room?.remoteParticipants.values.toList() ?? [];
    VideoTrack? remoteVideo;
    for (final p in remoteParticipants) {
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track is VideoTrack) {
          remoteVideo = pub.track as VideoTrack;
          break;
        }
      }
      if (remoteVideo != null) break;
    }

    VideoTrack? localVideo;
    for (final pub in _room?.localParticipant?.videoTrackPublications ?? const <LocalTrackPublication<LocalVideoTrack>>[]) {
      if (pub.track is VideoTrack) {
        localVideo = pub.track as VideoTrack;
        break;
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(_status, style: const TextStyle(fontSize: 15)),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: remoteVideo != null
                ? VideoTrackRenderer(remoteVideo)
                : const Center(
                    child: Text('等待对方画面...', style: TextStyle(color: Colors.white70)),
                  ),
          ),
          if (localVideo != null)
            Positioned(
              right: 16,
              bottom: 100,
              width: 110,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: VideoTrackRenderer(localVideo),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _toggleMute,
                  icon: Icon(_muted ? Icons.mic_off : Icons.mic, color: Colors.white),
                ),
                IconButton(
                  onPressed: _toggleCamera,
                  icon: Icon(_cameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white),
                ),
                IconButton(
                  onPressed: _toggleScreenShare,
                  icon: Icon(_screenSharing ? Icons.stop_screen_share : Icons.screen_share, color: Colors.white),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: _hangup,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
