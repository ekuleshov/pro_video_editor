import 'dart:io';

import 'package:flutter/foundation.dart';

/// Audio output formats supported for audio extraction.
///
/// Different platforms may have different support levels for each format.
enum AudioFormat {
  /// MP3 format - widely supported, good compression.
  /// Supported on: Android only (not supported on iOS/macOS)
  mp3,

  /// AAC format - high quality, modern codec.
  /// Supported on: Android, iOS, macOS
  aac,

  /// M4A format - Apple's container for AAC.
  /// Supported on: Android, iOS, macOS
  m4a,

  /// CAF format - Core Audio Format, Apple's flexible container.
  /// Supported on: iOS, macOS (Apple only)
  caf,

  /// WAV format - uncompressed audio, high quality, large file size.
  /// Supported on: Android, iOS, macOS
  wav,
}

/// Extension providing utility methods for [AudioFormat].
///
/// Offers access to file extensions, MIME types, and serialization names
/// for each audio format.
extension AudioFormatExtension on AudioFormat {
  /// Returns the file extension for this audio format.
  ///
  /// Note: AAC returns 'm4a' on iOS/macOS (as they cannot export raw .aac),
  /// but returns 'aac' on Android which supports raw AAC files.
  String get extension {
    switch (this) {
      case AudioFormat.mp3:
        return 'mp3';
      case AudioFormat.aac:
        // iOS/macOS can only export AAC in M4A container
        if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
          return 'm4a';
        }
        return 'aac';
      case AudioFormat.m4a:
        return 'm4a';
      case AudioFormat.caf:
        return 'caf';
      case AudioFormat.wav:
        return 'wav';
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
      case AudioFormat.caf:
        return 'audio/x-caf';
      case AudioFormat.wav:
        return 'audio/wav';
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
      case AudioFormat.caf:
        return 'caf';
      case AudioFormat.wav:
        return 'wav';
    }
  }
}
