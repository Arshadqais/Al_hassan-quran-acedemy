import 'dart:async';
import 'screen_annotations.dart';
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
  bool annotate = false;
  final annotations = <String, AnnotationSnapshot>{};
  @override
  void initState() {
    super.initState();
    listener = room.createListener()
      ..on<DataReceivedEvent>(receiveAnnotations)
      ..on<ParticipantConnectedEvent>((_) => resendAnnotations())
      ..on<RoomReconnectedEvent>((_) => resendAnnotations())
      ..listen((_) {
        if (mounted) {
          setState(() {
            final active = <String>{
              for (final p in <Participant>[
                ...room.remoteParticipants.values,
                ?room.localParticipant,
              ])
                for (final pub in p.videoTrackPublications)
                  if (pub.source == TrackSource.screenShareVideo && !pub.muted)
                    pub.sid,
            };
            annotations.removeWhere((sid, _) => !active.contains(sid));
          });
        }
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

  void receiveAnnotations(DataReceivedEvent event) {
    if (event.topic != annotationTopic ||
        !mounted ||
        widget.sessionActive?.value == false) {
      return;
    }
    final sender = event.participant;
    if (sender == null || !sender.permissions.canPublishData) return;
    final snapshot = AnnotationSnapshot.decode(event.data);
    if (snapshot == null ||
        !sender.videoTrackPublications.any(
          (p) =>
              p.sid == snapshot.track &&
              p.source == TrackSource.screenShareVideo &&
              !p.muted,
        )) {
      return;
    }
    if ((annotations[snapshot.track]?.revision ?? -1) >= snapshot.revision) {
      return;
    }
    setState(() => annotations[snapshot.track] = snapshot);
  }

  Future<void> sendAnnotations(String sid, List<Rect> rectangles) async {
    if (!widget.canShareScreen || widget.sessionActive?.value == false) return;
    final snapshot = AnnotationSnapshot(
      sid,
      (annotations[sid]?.revision ?? 0) + 1,
      rectangles,
    );
    setState(() => annotations[sid] = snapshot);
    try {
      await room.localParticipant?.publishData(
        snapshot.encode(),
        reliable: true,
        topic: annotationTopic,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Highlight could not be sent. Check your connection and draw again.',
            ),
          ),
        );
      }
    }
  }

  void resendAnnotations() {
    if (!widget.canShareScreen || widget.sessionActive?.value == false) return;
    for (final publication
        in room.localParticipant?.videoTrackPublications ?? []) {
      final snapshot = annotations[publication.sid];
      if (snapshot != null) {
        unawaited(sendAnnotations(publication.sid, snapshot.rectangles));
      }
    }
  }

  Widget screenTile(
    Participant owner,
    TrackPublication publication,
    VideoTrack track,
  ) {
    final dimensions = publication.dimensions;
    final ratio = dimensions != null && dimensions.height > 0
        ? dimensions.width / dimensions.height
        : 16 / 9;
    final editable = owner is LocalParticipant && widget.canShareScreen;
    return tile(
      '${owner.name} · Shared screen',
      Column(
        children: [
          if (editable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => annotate = !annotate),
                    icon: Icon(
                      annotate ? Icons.check : Icons.crop_free,
                      color: const Color(0xFFFFCC43),
                    ),
                    label: Text(
                      annotate ? 'Done highlighting' : 'Draw rectangle',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Clear highlights',
                    onPressed: () => sendAnnotations(publication.sid, []),
                    icon: const Icon(
                      Icons.layers_clear_outlined,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: ratio,
                child: ScreenAnnotationCanvas(
                  key: ValueKey(publication.sid),
                  enabled:
                      editable &&
                      annotate &&
                      widget.sessionActive?.value != false,
                  rectangles: annotations[publication.sid]?.rectangles ?? [],
                  onChanged: (rects) =>
                      unawaited(sendAnnotations(publication.sid, rects)),
                  child: VideoTrackRenderer(
                    track,
                    fit: VideoViewFit.contain,
                    mirrorMode: VideoViewMirrorMode.off,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
    final screens = <Widget>[];
    for (final participant in participants) {
      var hasVideo = false;
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is VideoTrack && !publication.muted) {
          hasVideo = true;
          if (publication.source == TrackSource.screenShareVideo) {
            screens.add(screenTile(participant, publication, track));
          } else {
            video.add(tile(participant.name, VideoTrackRenderer(track)));
          }
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
                  : screens.isNotEmpty
                  ? Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: screens.first,
                          ),
                        ),
                        if (video.isNotEmpty)
                          SizedBox(
                            height: 115,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              children: video
                                  .map(
                                    (v) => SizedBox(
                                      width: 160,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: v,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
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
      Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Semantics(
          label: label,
          button: true,
          excludeSemantics: true,
          enabled: !(connecting || changing || error.isNotEmpty),
          onTap: connecting || changing || error.isNotEmpty ? null : action,
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF315447),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(15),
            ),
            onPressed: connecting || changing || error.isNotEmpty
                ? null
                : action,
            icon: Icon(icon, color: Colors.white, size: 23),
          ),
        ),
      ),
      const SizedBox(height: 7),
      ExcludeSemantics(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
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
