import '/core/models/video/editor_video_model.dart';
import 'audio_format_model.dart';

/// Configuration for extracting audio from a video.
///
/// This model contains all necessary parameters for audio extraction:
/// - Video source
/// - Output audio format
/// - Quality settings (bitrate)
/// - Optional trimming (start/end time)
/// - Task ID for progress tracking
class AudioExtractConfigs {
  /// Creates an [AudioExtractConfigs] instance with the given parameters.
  ///
  /// [video] The source video to extract audio from.
  /// [format] The desired output audio format (default: [AudioFormat.mp3]).
  /// [bitrate] Audio bitrate in kbps (default: 128). Higher values = better
  /// quality.
  /// [startTime] Optional start time for trimming. If null, starts from
  /// beginning.
  /// [endTime] Optional end time for trimming. If null, goes to video end.
  /// [id] Unique task identifier. Generated automatically if not provided.
  AudioExtractConfigs({
    required this.video,
    this.format = AudioFormat.mp3,
    this.bitrate = 128,
    this.startTime,
    this.endTime,
    String? id,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  /// The source video to extract audio from.
  final EditorVideo video;

  /// The output audio format.
  final AudioFormat format;

  /// Audio bitrate in kilobits per second (kbps).
  ///
  /// Common values:
  /// - 64 kbps: Low quality (voice)
  /// - 128 kbps: Standard quality (default)
  /// - 192 kbps: High quality
  /// - 256 kbps: Very high quality
  /// - 320 kbps: Maximum quality (MP3)
  final int bitrate;

  /// Optional start time for trimming the audio.
  ///
  /// If provided, audio extraction will begin at this timestamp.
  /// If null, extraction starts from the beginning of the video.
  final Duration? startTime;

  /// Optional end time for trimming the audio.
  ///
  /// If provided, audio extraction will end at this timestamp.
  /// If null, extraction continues to the end of the video.
  final Duration? endTime;

  /// Unique identifier for tracking progress of this extraction task.
  ///
  /// Used with [ProVideoEditor.progressStreamById] to monitor extraction
  /// progress.
  final String id;

  /// Converts this configuration to a map for platform channel communication.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'format': format.name,
      'bitrate': bitrate,
      'startTime': startTime?.inMicroseconds,
      'endTime': endTime?.inMicroseconds,
    };
  }

  /// Creates a copy of this config with optional parameter overrides.
  AudioExtractConfigs copyWith({
    EditorVideo? video,
    AudioFormat? format,
    int? bitrate,
    Duration? startTime,
    Duration? endTime,
    String? id,
  }) {
    return AudioExtractConfigs(
      video: video ?? this.video,
      format: format ?? this.format,
      bitrate: bitrate ?? this.bitrate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      id: id ?? this.id,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AudioExtractConfigs &&
        other.video == video &&
        other.format == format &&
        other.bitrate == bitrate &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.id == id;
  }

  @override
  int get hashCode {
    return video.hashCode ^
        format.hashCode ^
        bitrate.hashCode ^
        startTime.hashCode ^
        endTime.hashCode ^
        id.hashCode;
  }

  @override
  String toString() {
    return 'AudioExtractConfigs(video: $video, format: $format, '
        'bitrate: $bitrate, startTime: $startTime, endTime: $endTime, id: $id)';
  }
}
