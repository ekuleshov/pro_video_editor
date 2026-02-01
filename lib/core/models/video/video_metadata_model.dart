import 'dart:ui';

import '/shared/utils/parser/double_parser.dart';
import '/shared/utils/parser/int_parser.dart';

/// A class that holds metadata information about a video.
class VideoMetadata {
  /// Creates a [VideoMetadata] instance.
  VideoMetadata({
    required this.duration,
    required this.extension,
    required this.fileSize,
    required this.originalResolution,
    required this.resolution,
    required this.rotation,
    required this.bitrate,
    this.audioDuration,
    this.title = '',
    this.artist = '',
    this.author = '',
    this.album = '',
    this.albumArtist = '',
    this.date,
    this.isOptimizedForStreaming,
  });

  /// Creates a [VideoMetadata] instance from a map of data.
  ///
  /// The [value] map contains metadata values such as duration, resolution,
  /// file size, and others.
  /// The [extension] is the video file format (e.g., 'mp4').
  factory VideoMetadata.fromMap(Map<dynamic, dynamic> value, String extension) {
    final originalResolution = Size(
      safeParseDouble(value['width']),
      safeParseDouble(value['height']),
    );
    int rotation = safeParseInt(value['rotation']);
    bool isNormalRotated = rotation % 180 == 0;

    return VideoMetadata(
      duration: Duration(milliseconds: safeParseInt(value['duration'])),
      extension: extension,
      fileSize: value['fileSize'] ?? 0,
      resolution:
          isNormalRotated ? originalResolution : originalResolution.flipped,
      originalResolution: originalResolution,
      rotation: rotation,
      bitrate: safeParseInt(value['bitrate']),
      audioDuration: value['audioDuration'] != null
          ? Duration(milliseconds: safeParseInt(value['audioDuration']))
          : null,
      title: value['title'] ?? '',
      artist: value['artist'] ?? '',
      author: value['author'] ?? '',
      album: value['album'] ?? '',
      albumArtist: value['albumArtist'] ?? '',
      date:
          (value['date'] ?? '') != '' ? DateTime.tryParse(value['date']) : null,
      isOptimizedForStreaming: value['isOptimizedForStreaming'] as bool?,
    );
  }

  /// The title of the video (e.g., the name of the movie or video).
  final String title;

  /// The artist associated with the video (e.g., the creator or performer).
  final String artist;

  /// The author of the video content.
  final String author;

  /// The album the video belongs to (if applicable).
  final String album;

  /// The album artist, typically used when the album contains works from
  /// multiple artists.
  final String albumArtist;

  /// The date when the video was created or released.
  final DateTime? date;

  /// The size of the video file in bytes.
  final int fileSize;

  /// The effective display resolution of the video, represented as a [Size]
  /// object.
  ///
  /// If the video is rotated by 90°, 270°, 450°, etc., the width and height
  /// values are automatically swapped to reflect the actual orientation as
  /// it appears in the video player.
  ///
  /// To retrieve the original, unrotated resolution, use [originalResolution].
  ///
  /// Example:
  /// ```dart
  /// Size(1920, 1080) // Full HD resolution
  /// ```
  final Size resolution;

  /// The original resolution of the video before any rotation is applied.
  ///
  /// Unlike [resolution], this value always represents the actual pixel
  /// dimensions of the video file, regardless of its orientation.
  ///
  /// Example:
  /// ```dart
  /// Size(1080, 1920) // Portrait video in raw file
  /// ```
  final Size originalResolution;

  /// The rotation of the video.
  final int rotation;

  /// The duration of the video.
  ///
  /// Example:
  /// ```dart
  /// Duration(seconds: 120) // 2 minutes
  /// ```
  final Duration duration;

  /// The duration of the audio track, if present.
  ///
  /// This value may differ from [duration] in cases where the audio track
  /// is shorter than the video. If the video has no audio track, this will
  /// be `null`.
  ///
  /// Example:
  /// ```dart
  /// Duration(seconds: 115) // Audio ends 5 seconds before video
  /// ```
  final Duration? audioDuration;

  /// The format of the video file, such as "mp4" or "avi".
  final String extension;

  /// The bitrate of the video in bits per second.
  ///
  /// This value represents the amount of data processed per unit of time in
  /// the video stream.
  /// Higher bitrate generally result in better video quality, but also
  /// larger file sizes.
  final int bitrate;

  /// Whether the video is optimized for progressive streaming.
  ///
  /// When `true`, the video's metadata (moov atom) is located at the beginning
  /// of the file, allowing browsers and media players to start playback before
  /// the entire file is downloaded.
  ///
  /// When `false`, the metadata is at the end of the file (mdat before moov),
  /// which requires downloading the entire file before playback can begin.
  ///
  /// This value is `null` for non-MP4/MOV formats or if the check couldn't
  /// be performed.
  ///
  /// To create streaming-optimized videos, set `shouldOptimizeForNetworkUse`
  /// to `true` when rendering.
  final bool? isOptimizedForStreaming;

  /// Returns a copy of this config with the given fields replaced.
  VideoMetadata copyWith({
    String? title,
    String? artist,
    String? author,
    String? album,
    String? albumArtist,
    DateTime? date,
    int? fileSize,
    Size? resolution,
    Size? originalResolution,
    int? rotation,
    Duration? duration,
    Duration? audioDuration,
    String? extension,
    int? bitrate,
    bool? isOptimizedForStreaming,
  }) {
    return VideoMetadata(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      author: author ?? this.author,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      date: date ?? this.date,
      fileSize: fileSize ?? this.fileSize,
      resolution: resolution ?? this.resolution,
      originalResolution: originalResolution ?? this.originalResolution,
      rotation: rotation ?? this.rotation,
      duration: duration ?? this.duration,
      audioDuration: audioDuration ?? this.audioDuration,
      extension: extension ?? this.extension,
      bitrate: bitrate ?? this.bitrate,
      isOptimizedForStreaming:
          isOptimizedForStreaming ?? this.isOptimizedForStreaming,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is VideoMetadata &&
        other.title == title &&
        other.artist == artist &&
        other.author == author &&
        other.album == album &&
        other.albumArtist == albumArtist &&
        other.date == date &&
        other.fileSize == fileSize &&
        other.resolution == resolution &&
        other.originalResolution == originalResolution &&
        other.rotation == rotation &&
        other.duration == duration &&
        other.audioDuration == audioDuration &&
        other.extension == extension &&
        other.bitrate == bitrate &&
        other.isOptimizedForStreaming == isOptimizedForStreaming;
  }

  @override
  int get hashCode {
    return title.hashCode ^
        artist.hashCode ^
        author.hashCode ^
        album.hashCode ^
        albumArtist.hashCode ^
        date.hashCode ^
        fileSize.hashCode ^
        resolution.hashCode ^
        originalResolution.hashCode ^
        rotation.hashCode ^
        duration.hashCode ^
        audioDuration.hashCode ^
        extension.hashCode ^
        bitrate.hashCode ^
        isOptimizedForStreaming.hashCode;
  }
}
