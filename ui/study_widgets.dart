import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';

class MediaCache {
  static final Map<String, Uint8List> _m = {};
  static final Map<String, Future<Uint8List>> _f = {};
  static Future<Uint8List> bytes(ApiClient api, String id) {
    final hit = _m[id];
    if (hit != null) return Future.value(hit);
    return _f[id] ??= api.studyMediaBytes(id).then((b) {
      _m[id] = b;
      if (_m.length > 40) _m.remove(_m.keys.first);
      return b;
    }).whenComplete(() => _f.remove(id));
  }
}

class StudyImage extends StatefulWidget {
  const StudyImage({super.key, this.assetId, this.url, this.width, this.height, this.fit = BoxFit.cover, this.radius = 0, this.icon = Icons.image_outlined});
  final String? assetId, url;
  final double? width, height;
  final BoxFit fit;
  final double radius;
  final IconData icon;
  @override
  State<StudyImage> createState() => _StudyImageState();
}

class _StudyImageState extends State<StudyImage> {
  Future<Uint8List>? _f;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant StudyImage old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId) _init();
  }

  void _init() {
    final id = widget.assetId;
    _f = id == null ? null : MediaCache.bytes(context.read<ApiClient>(), id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget ph(Widget c) => Container(color: cs.surfaceContainerHighest, alignment: Alignment.center, child: c);
    Widget body;
    if (widget.url != null) {
      body = Image.network(widget.url!, fit: widget.fit, width: widget.width, height: widget.height,
          errorBuilder: (_, __, ___) => ph(Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant)));
    } else if (_f != null) {
      body = FutureBuilder<Uint8List>(
        future: _f,
        builder: (_, s) {
          if (s.hasError) return ph(Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant));
          if (!s.hasData) return ph(const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
          return Image.memory(s.data!, fit: widget.fit, width: widget.width, height: widget.height, gaplessPlayback: true);
        },
      );
    } else {
      body = ph(Icon(widget.icon, color: cs.onSurfaceVariant));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: SizedBox(width: widget.width, height: widget.height, child: body));
  }
}

class StudyVideo extends StatefulWidget {
  const StudyVideo({super.key, required this.media});
  final StudyMedia media;
  @override
  State<StudyVideo> createState() => _StudyVideoState();
}

class _StudyVideoState extends State<StudyVideo> {
  VideoPlayerController? _c;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final api = context.read<ApiClient>();
    try {
      VideoPlayerController c;
      if (widget.media.url != null) {
        c = VideoPlayerController.networkUrl(Uri.parse(widget.media.url!));
      } else {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/study_${widget.media.assetId}.mp4');
        if (!await f.exists() || await f.length() == 0) await api.studyMediaFile(widget.media.assetId!, f.path);
        c = VideoPlayerController.file(f);
      }
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() => _c = c);
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _c;
    if (_err) return Container(height: 160, color: cs.surfaceContainerHighest, alignment: Alignment.center, child: const Text('Vidéo indisponible'));
    if (c == null) return Container(height: 160, color: cs.surfaceContainerHighest, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2));
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: Stack(alignment: Alignment.center, children: [
          VideoPlayer(c),
          GestureDetector(
            onTap: () => c.value.isPlaying ? c.pause() : c.play(),
            child: AnimatedOpacity(
              opacity: c.value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                  width: 58, height: 58,
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38)),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.only(top: 6))),
        ]),
      ),
    );
  }
}

class MediaStrip extends StatelessWidget {
  const MediaStrip(this.items, {super.key, this.height = 190});
  final List<StudyMedia> items;
  final double height;

  void _zoom(BuildContext context, StudyMedia m) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          Positioned.fill(child: InteractiveViewer(child: Center(child: StudyImage(assetId: m.assetId, url: m.url, fit: BoxFit.contain)))),
          SafeArea(child: Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)))),
        ]),
      ),
    );
  }

  Widget _one(BuildContext context, StudyMedia m, {double? width}) {
    final cs = Theme.of(context).colorScheme;
    final w = m.isVideo
        ? StudyVideo(media: m)
        : GestureDetector(onTap: () => _zoom(context, m), child: StudyImage(assetId: m.assetId, url: m.url, width: width ?? double.infinity, height: height, radius: 16));
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        w,
        if ((m.caption ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.caption!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) return _one(context, items.first);
    final w = MediaQuery.of(context).size.width * 0.78;
    return SizedBox(
      height: height + 26,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _one(context, items[i], width: w),
      ),
    );
  }
}

class SponsorAvatar extends StatelessWidget {
  const SponsorAvatar(this.s, {super.key, this.size = 44});
  final SponsorBrief s;
  final double size;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final init = s.name.isEmpty ? '?' : s.name.characters.first.toUpperCase();
    return Stack(clipBehavior: Clip.none, children: [
      s.logoAssetId != null
          ? StudyImage(assetId: s.logoAssetId, width: size, height: size, radius: size * 0.3)
          : Container(width: size, height: size, alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(size * 0.3)),
              child: Text(init, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: size * 0.42))),
      if (s.verified)
        Positioned(right: -4, bottom: -4, child: Container(decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(Icons.verified_rounded, size: size * 0.38, color: const Color(0xFF2563EB)))),
    ]);
  }
}