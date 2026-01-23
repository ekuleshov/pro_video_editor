import 'dart:math' as math;

import 'package:flutter/material.dart';

import '/core/models/audio/waveform_data_model.dart';
import '../models/waveform_style.dart';

/// A widget that displays an audio waveform visualization.
///
/// This widget renders [WaveformData] as a series of vertical bars representing
/// audio amplitude over time. It supports both mono and stereo audio, with
/// stereo displaying left channel above and right channel below the center
/// line.
///
/// Example usage:
/// ```dart
/// AudioWaveform(
///   waveform: waveformData,
///   style: WaveformStyle(
///     waveColor: Colors.blue,
///     backgroundColor: Colors.black,
///   ),
/// )
/// ```
///
/// For interactive waveforms with selection, use [AudioWaveform.interactive]:
/// ```dart
/// AudioWaveform.interactive(
///   waveform: waveformData,
///   currentPosition: currentPositionMs,
///   onSeek: (positionMs) => player.seek(positionMs),
/// )
/// ```
class AudioWaveform extends StatelessWidget {
  /// Creates an [AudioWaveform] widget.
  ///
  /// [waveform] The waveform data to display.
  /// [style] Visual styling options for the waveform.
  /// [height] Height of the widget. Defaults to 80.
  const AudioWaveform({
    super.key,
    required this.waveform,
    this.style = const WaveformStyle(),
    this.height = 80,
  })  : currentPosition = null,
        onSeek = null,
        showPositionIndicator = false;

  /// Creates an interactive [AudioWaveform] with position indicator and
  /// seek support.
  ///
  /// [waveform] The waveform data to display.
  /// [currentPosition] Current playback position in milliseconds.
  /// [onSeek] Callback when user taps to seek. Receives position in
  /// milliseconds.
  /// [style] Visual styling options for the waveform.
  /// [height] Height of the widget. Defaults to 80.
  const AudioWaveform.interactive({
    super.key,
    required this.waveform,
    required int this.currentPosition,
    required this.onSeek,
    this.style = const WaveformStyle(),
    this.height = 80,
  }) : showPositionIndicator = true;

  /// The waveform data to render.
  final WaveformData waveform;

  /// Visual styling options for the waveform.
  final WaveformStyle style;

  /// Height of the widget in pixels.
  final double height;

  /// Current playback position in milliseconds (for interactive mode).
  final int? currentPosition;

  /// Callback when user seeks to a position. Receives position in milliseconds.
  final ValueChanged<int>? onSeek;

  /// Whether to show the position indicator line.
  final bool showPositionIndicator;

  @override
  Widget build(BuildContext context) {
    Widget child = ClipRRect(
      borderRadius: style.borderRadius ?? BorderRadius.zero,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _WaveformPainter(
          waveform: waveform,
          style: style,
          currentPosition: currentPosition,
          showPositionIndicator: showPositionIndicator,
        ),
      ),
    );

    if (onSeek != null && waveform.duration > 0) {
      child = GestureDetector(
        onTapDown: (details) => _handleTap(details, context),
        onHorizontalDragUpdate: (details) => _handleDrag(details, context),
        child: child,
      );
    }

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: style.borderRadius,
      ),
      child: child,
    );
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final position = details.localPosition.dx / box.size.width;
    final seekPosition = (position * waveform.duration).round();
    onSeek?.call(seekPosition.clamp(0, waveform.duration));
  }

  void _handleDrag(DragUpdateDetails details, BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final position = details.localPosition.dx / box.size.width;
    final seekPosition = (position * waveform.duration).round();
    onSeek?.call(seekPosition.clamp(0, waveform.duration));
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.waveform,
    required this.style,
    this.currentPosition,
    this.showPositionIndicator = false,
  });

  final WaveformData waveform;
  final WaveformStyle style;
  final int? currentPosition;
  final bool showPositionIndicator;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = waveform.leftChannel;
    if (samples.isEmpty) return;

    final totalBarWidth = style.barWidth + style.barSpacing;
    final barsCount = (size.width / totalBarWidth).floor();
    if (barsCount == 0) return;

    final samplesPerBar = samples.length / barsCount;
    final centerY = size.height / 2;
    final maxAmplitude =
        waveform.isStereo ? size.height / 4 - 2 : size.height / 2 - 2;

    // Calculate position for played/unplayed coloring
    final positionRatio = currentPosition != null && waveform.duration > 0
        ? currentPosition! / waveform.duration
        : 0.0;
    final playedBars = (barsCount * positionRatio).floor();

    // Prepare paints
    final unplayedPaint = Paint()
      ..color = style.waveColor
      ..strokeWidth = style.barWidth
      ..strokeCap = StrokeCap.round;

    final playedPaint = Paint()
      ..color = style.waveColorPlayed ?? style.waveColor
      ..strokeWidth = style.barWidth
      ..strokeCap = StrokeCap.round;

    final secondaryUnplayedPaint = Paint()
      ..color =
          style.secondaryWaveColor ?? style.waveColor.withValues(alpha: 0.6)
      ..strokeWidth = style.barWidth
      ..strokeCap = StrokeCap.round;

    final secondaryPlayedPaint = Paint()
      ..color = style.secondaryWaveColor?.withValues(alpha: 0.8) ??
          (style.waveColorPlayed ?? style.waveColor).withValues(alpha: 0.6)
      ..strokeWidth = style.barWidth
      ..strokeCap = StrokeCap.round;

    // Draw waveform bars
    for (int i = 0; i < barsCount; i++) {
      final startIdx = (i * samplesPerBar).floor();
      final endIdx = ((i + 1) * samplesPerBar).floor().clamp(0, samples.length);

      // Find peak in this range
      double leftPeak = 0;
      double rightPeak = 0;

      for (int j = startIdx; j < endIdx; j++) {
        leftPeak = math.max(leftPeak, samples[j]);
        if (waveform.rightChannel != null) {
          rightPeak = math.max(rightPeak, waveform.rightChannel![j]);
        }
      }

      final x = i * totalBarWidth + style.barWidth / 2;
      final isPlayed = i < playedBars;

      if (waveform.isStereo) {
        // Stereo: left channel above center, right below
        final leftHeight =
            (leftPeak * maxAmplitude).clamp(style.minBarHeight, maxAmplitude);
        final rightHeight =
            (rightPeak * maxAmplitude).clamp(style.minBarHeight, maxAmplitude);

        // Left channel (above center)
        canvas
          ..drawLine(
            Offset(x, centerY - 1),
            Offset(x, centerY - 1 - leftHeight),
            isPlayed ? playedPaint : unplayedPaint,
          )

          // Right channel (below center)
          ..drawLine(
            Offset(x, centerY + 1),
            Offset(x, centerY + 1 + rightHeight),
            isPlayed ? secondaryPlayedPaint : secondaryUnplayedPaint,
          );
      } else {
        // Mono: symmetric around center
        final height =
            (leftPeak * maxAmplitude).clamp(style.minBarHeight, maxAmplitude);
        canvas.drawLine(
          Offset(x, centerY - height),
          Offset(x, centerY + height),
          isPlayed ? playedPaint : unplayedPaint,
        );
      }
    }

    // Draw center line for stereo
    if (waveform.isStereo && style.showCenterLine) {
      final linePaint = Paint()
        ..color =
            style.centerLineColor ?? style.waveColor.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        linePaint,
      );
    }

    // Draw position indicator
    if (showPositionIndicator && currentPosition != null) {
      final indicatorX = size.width * positionRatio;
      final indicatorPaint = Paint()
        ..color = style.positionIndicatorColor ?? style.waveColor
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(indicatorX, 0),
        Offset(indicatorX, size.height),
        indicatorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.style != style;
  }
}
