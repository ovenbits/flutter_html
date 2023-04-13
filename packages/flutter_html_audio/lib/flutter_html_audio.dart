library flutter_html_audio;

import 'package:chewie_audio/chewie_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:video_player/video_player.dart';
import 'package:html/dom.dart' as dom;

typedef AudioControllerCallback = void Function(dom.Element?, ChewieAudioController, VideoPlayerController);

CustomRender audioRender({AudioControllerCallback? onControllerCreated}) => CustomRender.widget(widget: (context, buildChildren) => AudioWidget(context: context, callback: onControllerCreated));

CustomRenderMatcher audioMatcher() => (context) {
      return context.tree.element?.localName == "audio";
    };

class AudioWidget extends StatefulWidget {
  final RenderContext context;
  final AudioControllerCallback? callback;

  AudioWidget({
    required this.context,
    this.callback,
  });

  @override
  State<StatefulWidget> createState() => _AudioWidgetState();
}

class _AudioWidgetState extends State<AudioWidget> {
  ChewieAudioController? chewieAudioController;
  VideoPlayerController? audioController;
  late final List<String?> sources;

  @override
  void initState() {
    sources = <String?>[
      if (widget.context.tree.element?.attributes['src'] != null) widget.context.tree.element!.attributes['src'],
      ...ReplacedElement.parseMediaSources(widget.context.tree.element!.children),
    ];
    if (sources.isNotEmpty && sources.first != null) {
      audioController = VideoPlayerController.network(
        sources.first ?? "",
      );
      chewieAudioController = ChewieAudioController(
        videoPlayerController: audioController!,
        autoPlay: widget.context.tree.element?.attributes['autoplay'] != null,
        looping: widget.context.tree.element?.attributes['loop'] != null,
        showControls: widget.context.tree.element?.attributes['controls'] != null,
        autoInitialize: true,
      );
      widget.callback?.call(widget.context.tree.element, chewieAudioController!, audioController!);
    }
    super.initState();
  }

  @override
  void dispose() {
    chewieAudioController?.dispose();
    audioController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext bContext) {
    if (sources.isEmpty || sources.first == null) {
      return Container(height: 0, width: 0);
    }
    return Container(
      key: widget.context.key,
      width: widget.context.style.width ?? 300,
      height: Theme.of(bContext).platform == TargetPlatform.android ? 48 : 75,
      child: ChewieAudio(
        controller: chewieAudioController!,
      ),
    );
  }
}
