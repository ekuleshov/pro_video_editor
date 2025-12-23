import 'dart:ui';

/// Pre-defined video quality presets for common export scenarios.
///
/// Each preset defines standard resolution and bitrate combinations optimized
/// for different use cases, from high-quality 4K exports to web-optimized
/// low-quality videos.
enum VideoQualityPreset {
  /// Ultra High Definition (3840x2160)
  ///
  /// Best for: Professional content, theatrical displays
  /// - Resolution: 3840x2160
  /// - Bitrate: 45 Mbps
  ultra4K,

  /// 4K resolution (3840x2160)
  ///
  /// Best for: High-quality content, large screens
  /// - Resolution: 3840x2160
  /// - Bitrate: 35 Mbps
  k4,

  /// Full HD High Quality (1920x1080)
  ///
  /// Best for: High-quality social media, YouTube
  /// - Resolution: 1920x1080
  /// - Bitrate: 16 Mbps
  p1080High,

  /// Full HD Standard Quality (1920x1080)
  ///
  /// Best for: Standard social media, streaming
  /// - Resolution: 1920x1080
  /// - Bitrate: 8 Mbps
  p1080,

  /// HD High Quality (1280x720)
  ///
  /// Best for: Social media stories, streaming
  /// - Resolution: 1280x720
  /// - Bitrate: 5 Mbps
  p720High,

  /// HD Standard Quality (1280x720)
  ///
  /// Best for: Mobile viewing, web uploads
  /// - Resolution: 1280x720
  /// - Bitrate: 3 Mbps
  p720,

  /// Standard Definition (854x480)
  ///
  /// Best for: Fast uploads, limited bandwidth
  /// - Resolution: 854x480
  /// - Bitrate: 2.5 Mbps
  p480,

  /// Low Quality (640x360)
  ///
  /// Best for: Preview videos, very limited bandwidth
  /// - Resolution: 640x360
  /// - Bitrate: 1 Mbps
  low,

  /// Custom quality (user-defined settings)
  ///
  /// Use this when you want to specify your own bitrate and resolution
  custom,
}

/// Extension methods for [VideoQualityPreset] providing bitrate and
/// resolution values.
extension VideoQualityPresetX on VideoQualityPreset {
  /// Returns the bitrate in bits per second for this preset.
  ///
  /// For [VideoQualityPreset.custom], returns a default of 8 Mbps.
  int get bitrate {
    switch (this) {
      case VideoQualityPreset.ultra4K:
        return 45000000; // 45 Mbps
      case VideoQualityPreset.k4:
        return 35000000; // 35 Mbps
      case VideoQualityPreset.p1080High:
        return 16000000; // 16 Mbps
      case VideoQualityPreset.p1080:
        return 8000000; // 8 Mbps
      case VideoQualityPreset.p720High:
        return 5000000; // 5 Mbps
      case VideoQualityPreset.p720:
        return 3000000; // 3 Mbps
      case VideoQualityPreset.p480:
        return 2500000; // 2.5 Mbps
      case VideoQualityPreset.low:
        return 1000000; // 1 Mbps
      case VideoQualityPreset.custom:
        return 8000000; // Default 8 Mbps
    }
  }

  /// Returns the target resolution for this preset.
  ///
  /// For [VideoQualityPreset.custom], returns null to keep original resolution.
  Size? get resolution {
    switch (this) {
      case VideoQualityPreset.ultra4K:
      case VideoQualityPreset.k4:
        return const Size(3840, 2160);
      case VideoQualityPreset.p1080High:
      case VideoQualityPreset.p1080:
        return const Size(1920, 1080);
      case VideoQualityPreset.p720High:
      case VideoQualityPreset.p720:
        return const Size(1280, 720);
      case VideoQualityPreset.p480:
        return const Size(854, 480);
      case VideoQualityPreset.low:
        return const Size(640, 360);
      case VideoQualityPreset.custom:
        return null; // Keep original resolution
    }
  }

  /// Returns a human-readable description of this preset.
  String get description {
    switch (this) {
      case VideoQualityPreset.ultra4K:
        return 'Ultra HD 4K (3840x2160, 45 Mbps)';
      case VideoQualityPreset.k4:
        return '4K (3840x2160, 35 Mbps)';
      case VideoQualityPreset.p1080High:
        return 'Full HD High (1920x1080, 16 Mbps)';
      case VideoQualityPreset.p1080:
        return 'Full HD (1920x1080, 8 Mbps)';
      case VideoQualityPreset.p720High:
        return 'HD High (1280x720, 5 Mbps)';
      case VideoQualityPreset.p720:
        return 'HD (1280x720, 3 Mbps)';
      case VideoQualityPreset.p480:
        return 'SD (854x480, 2.5 Mbps)';
      case VideoQualityPreset.low:
        return 'Low (640x360, 1 Mbps)';
      case VideoQualityPreset.custom:
        return 'Custom';
    }
  }
}
