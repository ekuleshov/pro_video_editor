import 'package:flutter/foundation.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

/// A model describing settings for rendering or exporting a video.
///
/// Includes input video data (single video or multiple clips), optional
/// overlays, transformations, color filters, audio options, playback settings,
/// and output format.
class VideoRenderData {
  /// Creates a [VideoRenderData] with the given parameters.
  ///
  /// **Important:** You must provide either [video] OR [videoClips], but not
  /// both.
  /// - Use [video] for a single video with optional [startTime] and [endTime]
  /// - Use [videoClips] for concatenating multiple videos, each with their
  ///   own trim settings
  VideoRenderData({
    this.outputFormat = VideoOutputFormat.mp4,
    this.video,
    this.videoClips,
    this.imageBytes,
    this.transform,
    this.enableAudio = true,
    this.playbackSpeed,
    this.startTime,
    this.endTime,
    this.blur,
    this.bitrate,
    this.colorMatrixList = const [],
    this.qualityConfig,
    this.customAudioPath,
    this.originalAudioVolume,
    this.customAudioVolume,
    String? id,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        assert(
          (video != null) != (videoClips != null),
          'You must provide either video OR videoClips, but not both',
        ),
        assert(
          videoClips == null || videoClips.isNotEmpty,
          'videoClips must not be empty if provided',
        ),
        assert(
          startTime == null || endTime == null || startTime < endTime,
          'startTime must be before endTime',
        ),
        assert(
          blur == null || blur >= 0,
          '[blur] must be greater than or equal to 0',
        ),
        assert(
          playbackSpeed == null || playbackSpeed > 0,
          '[playbackSpeed] must be greater than 0',
        ),
        assert(
          bitrate == null || bitrate > 0,
          '[bitrate] must be greater than 0',
        ),
        assert(
          originalAudioVolume == null || originalAudioVolume >= 0,
          '[originalAudioVolume] must be greater than or equal to 0',
        ),
        assert(
          customAudioVolume == null || customAudioVolume >= 0,
          '[customAudioVolume] must be greater than or equal to 0',
        );

  /// Creates a [VideoRenderData] with a predefined quality preset.
  ///
  /// This factory constructor simplifies video export by providing common
  /// quality configurations. The preset automatically sets the appropriate
  /// bitrate and resolution.
  ///
  /// Example:
  /// ```dart
  /// var model = RenderVideoModel.withQualityPreset(
  ///   video: EditorVideo.asset('assets/my-video.mp4'),
  ///   qualityPreset: VideoQualityPreset.p1080,
  ///   outputFormat: VideoOutputFormat.mp4,
  /// );
  /// ```
  ///
  /// You can override the preset's resolution by providing a custom
  /// [transform] with scale or crop settings. The bitrate from the preset
  /// will still be used unless explicitly overridden with [bitrateOverride].
  factory VideoRenderData.withQualityPreset({
    required EditorVideo video,
    required VideoQualityPreset qualityPreset,
    VideoOutputFormat outputFormat = VideoOutputFormat.mp4,
    Uint8List? imageBytes,
    ExportTransform? transform,
    bool enableAudio = true,
    double? playbackSpeed,
    Duration? startTime,
    Duration? endTime,
    double? blur,
    int? bitrateOverride,
    List<List<double>> colorMatrixList = const [],
    String? customAudioPath,
    double? originalAudioVolume,
    double? customAudioVolume,
    String? id,
  }) {
    final qualityConfig = VideoQualityConfig.fromPreset(qualityPreset);

    return VideoRenderData(
      id: id,
      outputFormat: outputFormat,
      video: video,
      imageBytes: imageBytes,
      transform: transform,
      enableAudio: enableAudio,
      playbackSpeed: playbackSpeed,
      startTime: startTime,
      endTime: endTime,
      blur: blur,
      bitrate: bitrateOverride ?? qualityConfig.bitrate,
      colorMatrixList: colorMatrixList,
      qualityConfig: qualityConfig,
      customAudioPath: customAudioPath,
      originalAudioVolume: originalAudioVolume,
      customAudioVolume: customAudioVolume,
    );
  }

  /// Unique ID for the task, useful when running multiple tasks at once.
  final String id;

  /// Configuration class that defines video quality parameters.
  final VideoQualityConfig? qualityConfig;

  /// The target format for the exported video.
  final VideoOutputFormat outputFormat;

  /// A model that encapsulates various ways to load and represent a video.
  ///
  /// This class supports videos from in-memory bytes, file system, network,
  /// or asset bundle. It provides convenience methods for identifying the
  /// source type and safely retrieving video bytes.
  ///
  /// **Note:** Either [video] or [videoClips] must be provided, but not both.
  /// Use this field for a single video. For concatenating multiple videos,
  /// use [videoClips] instead.
  final EditorVideo? video;

  /// A list of video clips to be concatenated into a single output video.
  ///
  /// Each clip can have its own start and end time for trimming. The clips
  /// will be joined in the order they appear in the list.
  ///
  /// **Note:** Either [video] or [videoClips] must be provided, but not both.
  /// Use this field for concatenating multiple videos. For a single video,
  /// use [video] instead.
  ///
  /// **Example:**
  /// ```dart
  /// videoClips: [
  ///   VideoClipModel(
  ///     video: EditorVideo.file('video1.mp4'),
  ///     startTime: Duration(seconds: 0),
  ///     endTime: Duration(seconds: 5),
  ///   ),
  ///   VideoClipModel(
  ///     video: EditorVideo.file('video2.mp4'),
  ///     startTime: Duration(seconds: 2),
  ///     endTime: Duration(seconds: 8),
  ///   ),
  /// ]
  /// ```
  final List<VideoSegment>? videoClips;

  /// A transparent image which will overlay the video.
  final Uint8List? imageBytes;

  /// Transformation settings like resize, rotation, offset, and flipping.
  ///
  /// Used to control how the video or image is positioned and modified during
  /// export.
  final ExportTransform? transform;

  /// Whether to include audio in the exported video.
  ///
  /// **Default**: `true`
  final bool enableAudio;

  /// Playback speed of the exported video.
  ///
  /// For example, `0.5` for half speed, `2.0` for double speed.
  final double? playbackSpeed;

  /// Optional start time for trimming the video.
  final Duration? startTime;

  /// Optional end time for trimming the video.
  final Duration? endTime;

  /// A 4x5 matrix used to apply color filters (e.g., saturation, brightness).
  final List<List<double>> colorMatrixList;

  /// Amount of blur to apply.
  ///
  /// Higher values result in a stronger blur effect.
  final double? blur;

  /// The bitrate of the video in bits per second.
  ///
  /// This value is optional and may be `null` if the bitrate is not specified.
  ///
  /// **WARNING Android:** Not all devices support CBR (Constant Bitrate) mode.
  /// If unsupported, the encoder may silently fall back to VBR
  /// (Variable Bitrate), and the actual bitrate may be constrained by
  /// device-specific minimum and maximum limits.
  ///
  /// **WARNING macOS iOS** It's not supported to directly set a specific
  /// bitrate, instant it will choose a preset which is the most near to the
  /// applied bitrate.
  final int? bitrate;

  /// Path to a custom audio file to be mixed with the video.
  ///
  /// When provided, this audio will be mixed with the original video audio.
  /// Use [originalAudioVolume] and [customAudioVolume] to control the mix
  /// levels of each audio track.
  final String? customAudioPath;

  /// Volume multiplier for the original video audio track.
  ///
  /// - Range: `0.0` (mute) to `1.0+` (amplify)
  /// - Default: `1.0` (unchanged)
  ///
  /// **Examples:**
  /// - `0.0`: Mute original audio completely
  /// - `0.5`: Reduce original audio to 50%
  /// - `1.0`: Keep original volume (default)
  /// - `1.5`: Amplify original audio by 50%
  /// - `2.0`: Double the original volume
  ///
  /// This parameter is only effective when [enableAudio] is `true`.
  final double? originalAudioVolume;

  /// Volume multiplier for the custom audio track.
  ///
  /// - Range: `0.0` (mute) to `1.0+` (amplify)
  /// - Default: `1.0` (unchanged)
  ///
  /// **Examples:**
  /// - `0.0`: Mute custom audio
  /// - `0.3`: Subtle background music (30%)
  /// - `0.5`: Equal mix with original audio
  /// - `1.0`: Full volume (default)
  /// - `1.2`: Slightly amplified
  ///
  /// This parameter is only effective when [customAudioPath] is provided.
  final double? customAudioVolume;

  /// Returns a [Stream] of [ProgressModel] objects that provides updates on
  /// the progress of the video rendering process associated with this model's
  /// [id].
  ///
  /// The stream is obtained from the [ProVideoEditor] singleton instance and
  /// is specific to the current video's identifier.
  Stream<ProgressModel> get progressStream {
    return ProVideoEditor.instance.progressStreamById(id);
  }

  /// Extracts the file extension from the video or first video clip.
  ///
  /// This is a convenience method for platform channel implementations that
  /// need to determine the output format based on the input video.
  ///
  /// The method checks in this order:
  /// 1. First clip in `videoClips` if present
  /// 2. Single `video` if present
  /// 3. Defaults to 'mp4' if neither is found
  ///
  /// Returns the file extension (without dot), e.g., 'mp4', 'mov'.
  ///
  /// Example:
  /// ```dart
  /// final model = RenderVideoModel(
  ///   video: EditorVideo.file('path/to/video.mov'),
  ///   outputFormat: VideoOutputFormat.mov,
  /// );
  /// final ext = await model.getVideoExtension();
  /// // ext: 'mov'
  /// ```
  Future<String> _getFirstVideoExtension() async {
    String? filePath;

    // Try to get from videoClips first
    if (videoClips != null && videoClips!.isNotEmpty) {
      filePath = await videoClips!.first.video.safeFilePath();
    }
    // Otherwise try single video
    else if (video != null) {
      filePath = await video!.safeFilePath();
    }

    return filePath != null ? _getFileExtension(filePath) : 'mp4';
  }

  /// Helper method to extract file extension from a file path.
  static String _getFileExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1 || lastDot == path.length - 1) {
      return 'mp4'; // default
    }
    return path.substring(lastDot + 1).toLowerCase();
  }

  /// Converts the model into a serializable map.
  Future<Map<String, dynamic>> toAsyncMap() async {
    var transform = this.transform ?? const ExportTransform();

    double? scaleX = transform.scaleX;
    double? scaleY = transform.scaleY;

    // Handle quality config for single video
    if (qualityConfig != null &&
        scaleX == null &&
        scaleY == null &&
        video != null) {
      final meta = await ProVideoEditor.instance.getMetadata(video!);
      final originalResolution = meta.resolution;
      final targetResolution = qualityConfig!.resolution ?? originalResolution;
      scaleX = targetResolution.width / originalResolution.width;
      scaleY = targetResolution.height / originalResolution.height;
    }

    // Convert video clips to map format
    List<Map<String, dynamic>>? videoClipsMaps;
    if (videoClips != null) {
      videoClipsMaps = await Future.wait(
        videoClips!.map((clip) => clip.toAsyncMap()),
      );
    } else if (video != null) {
      // Single video: convert to single clip format
      videoClipsMaps = [
        {
          'inputPath': await video!.safeFilePath(),
          'startUs': startTime?.inMicroseconds,
          'endUs': endTime?.inMicroseconds,
        }
      ];
    }

    return {
      ...transform.toMap(),
      'id': id,
      'inputFormat': await _getFirstVideoExtension(),
      'videoClips': videoClipsMaps,
      'imageBytes': imageBytes,
      'enableAudio': enableAudio,
      'playbackSpeed': playbackSpeed,
      'colorMatrixList': colorMatrixList,
      'outputFormat': outputFormat.name,
      'blur': blur,
      'bitrate': bitrate,
      'scaleX': scaleX,
      'scaleY': scaleY,
      'customAudioPath': customAudioPath,
      'originalAudioVolume': originalAudioVolume,
      'customAudioVolume': customAudioVolume,
    };
  }

  /// Creates a copy with updated values.
  VideoRenderData copyWith({
    String? id,
    VideoOutputFormat? outputFormat,
    EditorVideo? video,
    List<VideoSegment>? videoClips,
    Uint8List? imageBytes,
    ExportTransform? transform,
    bool? enableAudio,
    double? playbackSpeed,
    Duration? startTime,
    Duration? endTime,
    List<List<double>>? colorMatrixList,
    double? blur,
    int? bitrate,
    VideoQualityConfig? qualityConfig,
    String? customAudioPath,
    double? originalAudioVolume,
    double? customAudioVolume,
  }) {
    return VideoRenderData(
      id: id ?? this.id,
      outputFormat: outputFormat ?? this.outputFormat,
      video: video ?? this.video,
      videoClips: videoClips ?? this.videoClips,
      imageBytes: imageBytes ?? this.imageBytes,
      transform: transform ?? this.transform,
      enableAudio: enableAudio ?? this.enableAudio,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      colorMatrixList: colorMatrixList ?? this.colorMatrixList,
      blur: blur ?? this.blur,
      bitrate: bitrate ?? this.bitrate,
      qualityConfig: qualityConfig ?? this.qualityConfig,
      customAudioPath: customAudioPath ?? this.customAudioPath,
      originalAudioVolume: originalAudioVolume ?? this.originalAudioVolume,
      customAudioVolume: customAudioVolume ?? this.customAudioVolume,
    );
  }
}

/// Supported video output formats for export.
enum VideoOutputFormat {
  /// MPEG-4 Part 14, widely supported.
  mp4,

  /// mov format.
  ///
  /// Only supported on macos and ios.
  mov,
}
