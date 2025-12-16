import 'package:pro_video_editor/pro_video_editor.dart';

/// Represents a single video clip to be included in a video composition.
///
/// Each clip can have its own start and end time for trimming.
/// Multiple clips can be combined to create a concatenated video.
class VideoSegment {
  /// Creates a [VideoSegment] with the given parameters.
  const VideoSegment({
    required this.video,
    this.startTime,
    this.endTime,
  }) : assert(
          startTime == null || endTime == null || startTime < endTime,
          'startTime must be before endTime',
        );

  /// The video source for this clip.
  ///
  /// This class supports videos from in-memory bytes, file system, network,
  /// or asset bundle.
  final EditorVideo video;

  /// Optional start time for trimming this clip.
  ///
  /// If null, the clip starts from the beginning of the video.
  final Duration? startTime;

  /// Optional end time for trimming this clip.
  ///
  /// If null, the clip plays until the end of the video.
  final Duration? endTime;

  /// Converts this clip to a map for platform channel communication.
  Future<Map<String, dynamic>> toAsyncMap() async {
    final inputPath = await video.safeFilePath();

    return {
      'inputPath': inputPath,
      'startUs': startTime?.inMicroseconds,
      'endUs': endTime?.inMicroseconds,
    };
  }

  /// Creates a copy with updated values.
  VideoSegment copyWith({
    EditorVideo? video,
    Duration? startTime,
    Duration? endTime,
  }) {
    return VideoSegment(
      video: video ?? this.video,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is VideoSegment &&
        other.video == video &&
        other.startTime == startTime &&
        other.endTime == endTime;
  }

  @override
  int get hashCode => Object.hash(video, startTime, endTime);

  @override
  String toString() {
    return 'VideoClipModel('
        'video: $video, '
        'startTime: $startTime, '
        'endTime: $endTime)';
  }
}
