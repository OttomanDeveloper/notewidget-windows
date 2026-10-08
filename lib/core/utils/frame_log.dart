import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame timings as JSON lines, off unless `WIN_NOTES_FRAME_LOG` names a file.
/// A widget test builds a tree under a fake clock and a temp directory, so it
/// cannot see a stall in real file IO or the platform text-input path (§3.27).
class FrameLog {
  FrameLog(this.path);

  final String path;

  File? _file;
  int _frames = 0;
  int _worstBuild = 0;
  int _worstRaster = 0;

  /// Whether a log is being written, so a caller can skip the work entirely.
  /// An env var rather than a build flag because the interesting build is the
  /// release one, and a release build is what a person is actually using.
  static bool get enabled =>
      Platform.environment['WIN_NOTES_FRAME_LOG']?.isNotEmpty ?? false;

  /// Starts recording. Safe to call when disabled - it returns without
  /// registering anything, so no call site needs a guard.
  static void attachIfEnabled() {
    final String? target = Platform.environment['WIN_NOTES_FRAME_LOG'];
    if (target == null || target.isEmpty) return;
    final FrameLog log = FrameLog(target);
    SchedulerBinding.instance.addTimingsCallback(log.record);
  }

  /// `build_ms` is Dart including layout, `raster_ms` is the GPU thread. Both
  /// small on a frame you watched being late means the stall is not in that
  /// frame at all, which is the answer that redirects the search.
  void record(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    _file ??= File(path)..writeAsStringSync('', mode: FileMode.append);
    final StringBuffer out = StringBuffer();
    for (final FrameTiming t in timings) {
      final int build = t.buildDuration.inMicroseconds ~/ 1000;
      final int raster = t.rasterDuration.inMicroseconds ~/ 1000;
      final int total = t.totalSpan.inMicroseconds ~/ 1000;
      _frames++;
      if (build > _worstBuild) _worstBuild = build;
      if (raster > _worstRaster) _worstRaster = raster;
      out.writeln(jsonEncode(<String, Object?>{
        'frame': t.frameNumber,
        'build_ms': build,
        'raster_ms': raster,
        'total_ms': total,
      }));
    }
    _file!.writeAsStringSync(out.toString(), mode: FileMode.append, flush: true);
    if (kDebugMode) {
      debugPrint('frames=$_frames worstBuild=${_worstBuild}ms '
          'worstRaster=${_worstRaster}ms');
    }
  }
}