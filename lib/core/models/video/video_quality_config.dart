import 'dart:ui';

import 'video_quality_preset.dart';

/// Configuration class that defines video quality parameters.
///
/// This class encapsulates the bitrate and resolution settings for a given
/// quality preset. It provides factory constructors to create configurations
/// from presets or custom values.
class VideoQualityConfig {
  /// Creates a video quality configuration with the given parameters.
  const VideoQualityConfig({
    required this.bitrate,
    required this.resolution,
    required this.preset,
  });

  /// Creates a configuration from a [VideoQualityPreset].
  ///
  /// Returns appropriate bitrate and resolution for the given preset.
  /// For [VideoQualityPreset.custom], returns null resolution and a default
  /// bitrate of 8 Mbps.
  factory VideoQualityConfig.fromPreset(VideoQualityPreset preset) {
    return VideoQualityConfig(
      bitrate: preset.bitrate,
      resolution: preset.resolution,
      preset: preset,
    );
  }

  /// Creates a custom configuration with specific bitrate and resolution.
  ///
  /// Useful when you need fine-grained control over quality settings.
  factory VideoQualityConfig.custom({
    required int bitrate,
    Size? resolution,
  }) {
    return VideoQualityConfig(
      bitrate: bitrate,
      resolution: resolution,
      preset: VideoQualityPreset.custom,
    );
  }

  /// The target bitrate in bits per second.
  ///
  /// Higher bitrates generally result in better quality but larger file sizes.
  final int bitrate;

  /// The target resolution (width x height) for the video.
  ///
  /// If null, the original video resolution will be maintained.
  final Size? resolution;

  /// The quality preset used for this configuration.
  final VideoQualityPreset preset;

  /// Creates a copy of this configuration with optional overrides.
  VideoQualityConfig copyWith({
    int? bitrate,
    Size? resolution,
    VideoQualityPreset? preset,
  }) {
    return VideoQualityConfig(
      bitrate: bitrate ?? this.bitrate,
      resolution: resolution ?? this.resolution,
      preset: preset ?? this.preset,
    );
  }

  @override
  String toString() {
    return 'VideoQualityConfig(preset: ${preset.description}, bitrate: '
        '${bitrate ~/ 1000000}Mbps, resolution: '
        '${resolution?.width.toInt()}x${resolution?.height.toInt()})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is VideoQualityConfig &&
        other.bitrate == bitrate &&
        other.resolution == resolution &&
        other.preset == preset;
  }

  @override
  int get hashCode => Object.hash(bitrate, resolution, preset);
}
