/// Audio output formats supported for audio extraction.
///
/// Different platforms may have different support levels for each format.
enum AudioFormat {
  /// MP3 format - widely supported, good compression.
  mp3,

  /// AAC format - high quality, modern codec.
  aac,

  /// M4A format - Apple's container for AAC.
  m4a,
}

/// Extension providing utility methods for [AudioFormat].
///
/// Offers access to file extensions, MIME types, and serialization names
/// for each audio format.
extension AudioFormatExtension on AudioFormat {
  /// Returns the file extension for this audio format.
  String get extension {
    switch (this) {
      case AudioFormat.mp3:
        return 'mp3';
      case AudioFormat.aac:
        return 'aac';
      case AudioFormat.m4a:
        return 'm4a';
    }
  }

  /// Returns the MIME type for this audio format.
  String get mimeType {
    switch (this) {
      case AudioFormat.mp3:
        return 'audio/mpeg';
      case AudioFormat.aac:
        return 'audio/aac';
      case AudioFormat.m4a:
        return 'audio/mp4';
    }
  }

  /// Returns the name of the format for serialization.
  String get name {
    switch (this) {
      case AudioFormat.mp3:
        return 'mp3';
      case AudioFormat.aac:
        return 'aac';
      case AudioFormat.m4a:
        return 'm4a';
    }
  }
}
