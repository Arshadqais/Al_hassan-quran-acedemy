import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// A private, backend-authorized classroom. Media stays off until a user enables it.
class Classroom extends StatefulWidget {
  final String url, token, title;
  final bool canShareScreen;
  final Widget? chat;
  final ValueListenable<bool>? sessionActive;
  const Classroom({
    super.key,
    required this.url,
    required this.token,
    required this.title,
    required this.canShareScreen,
    this.chat,
    this.sessionActive,
  });
  @override
  State<Classroom> createState() => _ClassroomState();
}

class _ClassroomState extends State<Classroom> {
  final room = Room(
    roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
  );
  EventsListener<RoomEvent>? listener;
  bool connecting = true, changing = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    listener = room.createListener()
      ..listen((_) {
        if (mounted) setState(() {});
      });
    widget.sessionActive?.addListener(sessionChanged);
    connect();
  }

  Future<void> connect() async {
    try {
      await room.connect(widget.url, widget.token);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not connect to the private classroom. Check your connection and return to classes to try again.',
        );
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  @override
  void dispose() {
    widget.sessionActive?.removeListener(sessionChanged);
    unawaited(cleanup());
    super.dispose();
  }

  Future<void>? cleanupFuture;
  void sessionChanged() {
    if (widget.sessionActive?.value == false && mounted) {
      setState(
        () => error =
            'Your academy session ended. Leave the classroom and sign in again.',
      );
      unawaited(cleanup());
    }
  }

  Future<void> cleanup() => cleanupFuture ??= () async {
    await listener?.dispose();
    try {
      await room.disconnect();
    } finally {
      await room.dispose();
    }
  }();

  Future<void> change(Future<void> Function() action) async {
    if (changing) return;
    setState(() => changing = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Media could not be enabled. Check browser permissions or try a supported desktop browser.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = room.localParticipant;
    final participants = <Participant>[
      ...room.remoteParticipants.values,
      ?local,
    ];
    final video = <Widget>[];
    for (final participant in participants) {
      var hasVideo = false;
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is VideoTrack && !publication.muted) {
          hasVideo = true;
          video.add(tile(participant.name, VideoTrackRenderer(track)));
        }
      }
      if (!hasVideo) {
        video.add(
          tile(
            participant.name,
            const Center(
              child: Icon(
                Icons.person_outline,
                color: Color(0xFFBED3BF),
                size: 66,
              ),
            ),
          ),
        );
      }
    }
    return Scaffold(
      endDrawer: widget.chat == null || widget.sessionActive?.value == false
          ? null
          : SizedBox(
              width: (MediaQuery.sizeOf(context).width * .9)
                  .clamp(240, 400)
                  .toDouble(),
              child: Drawer(child: widget.chat),
            ),
      backgroundColor: const Color(0xFF102D25),
      appBar: AppBar(
        backgroundColor: const Color(0xFF143B30),
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 18)),
        actions: [
          if (widget.chat != null && widget.sessionActive?.value != false)
            Builder(
              builder: (drawerContext) => IconButton(
                tooltip: 'Open private chat',
                onPressed: () => Scaffold.of(drawerContext).openEndDrawer(),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Leave class',
              style: TextStyle(color: Color(0xFFF5C2B6)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'PRIVATE CLASSROOM · Camera and microphone start off. Enable them when you are ready.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFCADCCD), fontSize: 11),
              ),
            ),
            Expanded(
              child: connecting
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : error.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.8,
                          ),
                        ),
                      ),
                    )
                  : video.isEmpty
                  ? const Center(
                      child: Text(
                        'Waiting for your teacher…',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, c) => GridView.count(
                        crossAxisCount: c.maxWidth < 700 ? 1 : 2,
                        childAspectRatio: 1.5,
                        padding: const EdgeInsets.all(16),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        children: video,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (!room.canPlaybackAudio)
                    control(
                      Icons.volume_up_outlined,
                      'Enable audio',
                      () => change(room.startAudio),
                    ),
                  control(
                    local?.isMicrophoneEnabled() == true
                        ? Icons.mic
                        : Icons.mic_off_outlined,
                    'Microphone',
                    () => change(() async {
                      await local?.setMicrophoneEnabled(
                        !local.isMicrophoneEnabled(),
                      );
                    }),
                  ),
                  control(
                    local?.isCameraEnabled() == true
                        ? Icons.videocam
                        : Icons.videocam_off_outlined,
                    'Camera',
                    () => change(() async {
                      await local?.setCameraEnabled(!local.isCameraEnabled());
                    }),
                  ),
                  if (widget.canShareScreen)
                    control(
                      Icons.screen_share_outlined,
                      local?.isScreenShareEnabled() == true
                          ? 'Stop sharing'
                          : 'Share screen',
                      () => change(() async {
                        await local?.setScreenShareEnabled(
                          !local.isScreenShareEnabled(),
                        );
                      }),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE85750),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.call_end, color: Color(0xFFFFB9A9)),
                    label: const Text(
                      'Leave',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget control(IconData icon, String label, VoidCallback action) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filledTonal(
        tooltip: label,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF315447),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(15),
        ),
        onPressed: connecting || changing || error.isNotEmpty ? null : action,
        icon: Icon(icon, color: Colors.white, size: 23),
      ),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
    ],
  );
  Widget tile(String name, Widget content) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Container(
      color: const Color(0xFF1D4637),
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                name.isEmpty ? 'Academy member' : name,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
