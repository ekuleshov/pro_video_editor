import 'package:flutter/widgets.dart';

/// Visual styling options for [AudioWaveform].
class WaveformStyle {
  /// Creates a [WaveformStyle].
  const WaveformStyle({
    this.waveColor = const Color(0xFF4CAF50),
    this.waveColorPlayed,
    this.secondaryWaveColor,
    this.backgroundColor = const Color(0xFF212121),
    this.positionIndicatorColor,
    this.centerLineColor,
    this.barWidth = 3.0,
    this.barSpacing = 1.0,
    this.minBarHeight = 2.0,
    this.borderRadius,
    this.showCenterLine = true,
  });

  /// Color for the waveform bars (left channel in stereo).
  final Color waveColor;

  /// Color for the played portion of the waveform.
  /// If null, uses [waveColor].
  final Color? waveColorPlayed;

  /// Color for the right channel in stereo audio.
  /// If null, uses [waveColor] with reduced opacity.
  final Color? secondaryWaveColor;

  /// Background color of the waveform container.
  final Color backgroundColor;

  /// Color of the playback position indicator line.
  /// If null, uses [waveColor].
  final Color? positionIndicatorColor;

  /// Color of the center line (for stereo display).
  /// If null, uses [waveColor] with reduced opacity.
  final Color? centerLineColor;

  /// Width of each waveform bar in pixels.
  final double barWidth;

  /// Spacing between bars in pixels.
  final double barSpacing;

  /// Minimum height for bars (ensures quiet sections are visible).
  final double minBarHeight;

  /// Border radius for the waveform container.
  final BorderRadius? borderRadius;

  /// Whether to show the center line for stereo waveforms.
  final bool showCenterLine;

  /// Creates a copy of this style with the given fields replaced.
  WaveformStyle copyWith({
    Color? waveColor,
    Color? waveColorPlayed,
    Color? secondaryWaveColor,
    Color? backgroundColor,
    Color? positionIndicatorColor,
    Color? centerLineColor,
    double? barWidth,
    double? barSpacing,
    double? minBarHeight,
    BorderRadius? borderRadius,
    bool? showCenterLine,
  }) {
    return WaveformStyle(
      waveColor: waveColor ?? this.waveColor,
      waveColorPlayed: waveColorPlayed ?? this.waveColorPlayed,
      secondaryWaveColor: secondaryWaveColor ?? this.secondaryWaveColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      positionIndicatorColor:
          positionIndicatorColor ?? this.positionIndicatorColor,
      centerLineColor: centerLineColor ?? this.centerLineColor,
      barWidth: barWidth ?? this.barWidth,
      barSpacing: barSpacing ?? this.barSpacing,
      minBarHeight: minBarHeight ?? this.minBarHeight,
      borderRadius: borderRadius ?? this.borderRadius,
      showCenterLine: showCenterLine ?? this.showCenterLine,
    );
  }
}
