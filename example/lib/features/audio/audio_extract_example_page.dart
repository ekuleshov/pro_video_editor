import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

import '/core/constants/example_constants.dart';

/// A sample page demonstrating audio extraction from video files.
///
/// This widget showcases how to use the [ProVideoEditor] plugin to extract
/// audio tracks from video files with various formats and quality settings.
class AudioExtractExamplePage extends StatefulWidget {
  /// Creates an [AudioExtractExamplePage].
  const AudioExtractExamplePage({super.key});

  @override
  State<AudioExtractExamplePage> createState() =>
      _AudioExtractExamplePageState();
}

class _AudioExtractExamplePageState extends State<AudioExtractExamplePage> {
  String? _extractedAudioPath;
  bool _isExtracting = false;
  AudioFormat _selectedFormat = AudioFormat.mp3;
  final String _taskId = 'AudioExtractionTaskId';

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  // Audio track check states
  bool? _hasAudioTrack;
  bool? _mutedVideoHasAudio;
  bool _isCheckingAudio = false;

  // Waveform states
  WaveformData? _waveformData;
  bool _isGeneratingWaveform = false;
  WaveformResolution _selectedResolution = WaveformResolution.medium;
  final String _waveformTaskId = 'WaveformGenerationTaskId';

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();

    // Set default format based on platform
    if (!_isFormatSupported(_selectedFormat)) {
      // Find first supported format
      _selectedFormat = AudioFormat.values.firstWhere(
        _isFormatSupported,
        orElse: () => AudioFormat.m4a, // Fallback to M4A
      );
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() {
        _duration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _position = position;
      });
    });
  }

  Future<void> _extractAudio() async {
    setState(() {
      _isExtracting = true;
      _extractedAudioPath = null;
    });

    try {
      // Get output directory
      final directory = await getTemporaryDirectory();
      final outputPath = '${directory.path}/extracted_audio_'
          '${DateTime.now().millisecondsSinceEpoch}.'
          '${_selectedFormat.extension}';

      // Create extraction config
      final config = AudioExtractConfigs(
        video: EditorVideo.asset(kVideoEditorExampleAssetPath),
        format: _selectedFormat,
        // Optional: Add trimming
        // startTime: Duration(seconds: 5),
        // endTime: Duration(seconds: 15),
      );

      // Extract audio
      await ProVideoEditor.instance.extractAudioToFile(
        outputPath,
        config,
      );

      setState(() {
        _extractedAudioPath = outputPath;
        _isExtracting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio extracted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isExtracting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error extracting audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _playAudio() async {
    if (_extractedAudioPath == null) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(_extractedAudioPath!));
    }
  }

  Future<void> _deleteAudio() async {
    if (_extractedAudioPath == null) return;

    await _audioPlayer.stop();

    final file = File(_extractedAudioPath!);
    if (await file.exists()) {
      await file.delete();
    }

    setState(() {
      _extractedAudioPath = null;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
  }

  Future<void> _checkAudioTrack() async {
    setState(() {
      _isCheckingAudio = true;
      _hasAudioTrack = null;
      _mutedVideoHasAudio = null;
    });

    try {
      // Check if the demo video has audio
      final videoWithAudio = EditorVideo.asset(kVideoEditorExampleAssetPath);
      final hasAudio =
          await ProVideoEditor.instance.hasAudioTrack(videoWithAudio);

      // Check if the muted video has audio
      final mutedVideo = EditorVideo.asset('assets/demo_muted.mp4');
      final mutedHasAudio =
          await ProVideoEditor.instance.hasAudioTrack(mutedVideo);

      setState(() {
        _hasAudioTrack = hasAudio;
        _mutedVideoHasAudio = mutedHasAudio;
        _isCheckingAudio = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Demo video has audio: $hasAudio\nMuted video has audio: '
              '$mutedHasAudio',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isCheckingAudio = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking audio track: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Generates waveform data from the demo video.
  Future<void> _generateWaveform() async {
    setState(() {
      _isGeneratingWaveform = true;
      _waveformData = null;
    });

    try {
      final config = WaveformConfigs(
        video: EditorVideo.asset(kVideoEditorExampleAudio1Path),
        resolution: _selectedResolution,
        id: _waveformTaskId,
      );

      final waveform = await ProVideoEditor.instance.getWaveform(config);

      setState(() {
        _waveformData = waveform;
        _isGeneratingWaveform = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Waveform generated: ${waveform.sampleCount} samples, '
              '${waveform.isStereo ? "stereo" : "mono"}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isGeneratingWaveform = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating waveform: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Checks if an audio format is supported on the current platform.
  bool _isFormatSupported(AudioFormat format) {
    if (kIsWeb) return false; // Web not supported yet

    switch (format) {
      case AudioFormat.mp3:
        // MP3 only supported on Android
        return Platform.isAndroid;
      case AudioFormat.aac:
      case AudioFormat.m4a:
      case AudioFormat.wav:
        // AAC and M4A supported on all platforms
        return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
      case AudioFormat.caf:
        // CAF only supported on Apple platforms
        return Platform.isIOS || Platform.isMacOS;
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Extraction')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          _AudioExtractionCard(
            selectedFormat: _selectedFormat,
            isFormatSupported: _isFormatSupported,
            isExtracting: _isExtracting,
            taskId: _taskId,
            extractedAudioPath: _extractedAudioPath,
            isPlaying: _isPlaying,
            position: _position,
            duration: _duration,
            onFormatChanged: (format) => setState(() {
              _selectedFormat = format;
            }),
            onExtractAudio: _extractAudio,
            onPlayPause: _playAudio,
            onSeek: (value) async {
              await _audioPlayer.seek(Duration(seconds: value.toInt()));
            },
            onDelete: _deleteAudio,
          ),
          const SizedBox(height: 16),
          _AudioTrackDetectionCard(
            isCheckingAudio: _isCheckingAudio,
            hasAudioTrack: _hasAudioTrack,
            mutedVideoHasAudio: _mutedVideoHasAudio,
            onCheckAudioTrack: _checkAudioTrack,
          ),
          const SizedBox(height: 16),
          _WaveformGenerationCard(
            isGeneratingWaveform: _isGeneratingWaveform,
            selectedResolution: _selectedResolution,
            waveformData: _waveformData,
            waveformTaskId: _waveformTaskId,
            onResolutionChanged: (resolution) => setState(() {
              _selectedResolution = resolution;
            }),
            onGenerateWaveform: _generateWaveform,
          ),
        ],
      ),
    );
  }
}

class _AudioExtractionCard extends StatelessWidget {
  const _AudioExtractionCard({
    required this.selectedFormat,
    required this.isFormatSupported,
    required this.isExtracting,
    required this.taskId,
    required this.extractedAudioPath,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onFormatChanged,
    required this.onExtractAudio,
    required this.onPlayPause,
    required this.onSeek,
    required this.onDelete,
  });

  final AudioFormat selectedFormat;
  final bool Function(AudioFormat) isFormatSupported;
  final bool isExtracting;
  final String taskId;
  final String? extractedAudioPath;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final ValueChanged<AudioFormat> onFormatChanged;
  final VoidCallback onExtractAudio;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onDelete;

  String _formatDuration(Duration dur) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(dur.inMinutes.remainder(60));
    final seconds = twoDigits(dur.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audio Extraction',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select format and extract audio from video',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Format:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AudioFormat.values.map((format) {
                final isSupported = isFormatSupported(format);
                return Tooltip(
                  message: isSupported
                      ? 'Supported on this platform'
                      : 'Not supported on ${Platform.operatingSystem}',
                  child: ChoiceChip(
                    label: Text(format.name.toUpperCase()),
                    selected: selectedFormat == format,
                    onSelected: isSupported
                        ? (selected) {
                            if (selected) onFormatChanged(format);
                          }
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isExtracting ? null : onExtractAudio,
                icon: isExtracting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.audiotrack),
                label: Text(
                  isExtracting ? 'Extracting...' : 'Extract Audio',
                ),
              ),
            ),
            if (isExtracting) ...[
              const SizedBox(height: 8),
              _ExtractionProgressIndicator(
                taskId: taskId,
                isExtracting: isExtracting,
              ),
            ],
            // Extracted Audio Player
            if (extractedAudioPath != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Extracted Audio',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    iconSize: 48,
                    onPressed: onPlayPause,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Slider(
                value: position.inSeconds.toDouble(),
                max: duration.inSeconds.toDouble() > 0
                    ? duration.inSeconds.toDouble()
                    : 1,
                onChanged: onSeek,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position)),
                    Text(_formatDuration(duration)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'File: ${extractedAudioPath!.split('/').last}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AudioTrackDetectionCard extends StatelessWidget {
  const _AudioTrackDetectionCard({
    required this.isCheckingAudio,
    required this.hasAudioTrack,
    required this.mutedVideoHasAudio,
    required this.onCheckAudioTrack,
  });

  final bool isCheckingAudio;
  final bool? hasAudioTrack;
  final bool? mutedVideoHasAudio;
  final VoidCallback onCheckAudioTrack;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audio Track Detection',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check if videos have audio tracks before extraction',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isCheckingAudio ? null : onCheckAudioTrack,
                icon: isCheckingAudio
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.music_note),
                label: Text(
                  isCheckingAudio ? 'Checking...' : 'Check Audio Tracks',
                ),
              ),
            ),
            if (hasAudioTrack != null || mutedVideoHasAudio != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              if (hasAudioTrack != null) ...[
                _AudioTrackResultRow(
                  label: 'Demo video (with audio):',
                  hasAudio: hasAudioTrack!,
                ),
                const SizedBox(height: 8),
              ],
              if (mutedVideoHasAudio != null)
                _AudioTrackResultRow(
                  label: 'Muted video (no audio):',
                  hasAudio: mutedVideoHasAudio!,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AudioTrackResultRow extends StatelessWidget {
  const _AudioTrackResultRow({
    required this.label,
    required this.hasAudio,
  });

  final String label;
  final bool hasAudio;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          hasAudio ? Icons.check_circle : Icons.cancel,
          color: hasAudio ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(
          hasAudio ? 'Has audio' : 'No audio',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: hasAudio ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }
}

class _WaveformGenerationCard extends StatelessWidget {
  const _WaveformGenerationCard({
    required this.isGeneratingWaveform,
    required this.selectedResolution,
    required this.waveformData,
    required this.waveformTaskId,
    required this.onResolutionChanged,
    required this.onGenerateWaveform,
  });

  final bool isGeneratingWaveform;
  final WaveformResolution selectedResolution;
  final WaveformData? waveformData;
  final String waveformTaskId;
  final ValueChanged<WaveformResolution> onResolutionChanged;
  final VoidCallback onGenerateWaveform;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Waveform Generation',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Generate visual waveform data from video audio',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Resolution:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: WaveformResolution.values.map((resolution) {
                return ChoiceChip(
                  label: Text(
                    '${resolution.name.toUpperCase()} '
                    '(${resolution.samplesPerSecond}/s)',
                  ),
                  selected: selectedResolution == resolution,
                  onSelected: (selected) {
                    if (selected) onResolutionChanged(resolution);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isGeneratingWaveform ? null : onGenerateWaveform,
                icon: isGeneratingWaveform
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.waves),
                label: Text(
                  isGeneratingWaveform ? 'Generating...' : 'Generate Waveform',
                ),
              ),
            ),
            if (isGeneratingWaveform) ...[
              const SizedBox(height: 8),
              _WaveformProgressIndicator(taskId: waveformTaskId),
            ],
            if (waveformData != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _WaveformDisplay(waveformData: waveformData!),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaveformProgressIndicator extends StatelessWidget {
  const _WaveformProgressIndicator({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProgressModel>(
      stream: ProVideoEditor.instance.progressStreamById(taskId),
      builder: (context, snapshot) {
        final progress = snapshot.data?.progress ?? 0.0;
        return Column(
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        );
      },
    );
  }
}

class _WaveformDisplay extends StatefulWidget {
  const _WaveformDisplay({required this.waveformData});

  final WaveformData waveformData;

  @override
  State<_WaveformDisplay> createState() => _WaveformDisplayState();
}

class _WaveformDisplayState extends State<_WaveformDisplay> {
  int currentPosition = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Samples: ${widget.waveformData.sampleCount} | '
          'Duration: ${widget.waveformData.duration}ms | '
          '${widget.waveformData.isStereo ? "Stereo" : "Mono"}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        AudioWaveform.interactive(
          currentPosition: currentPosition,
          onSeek: (value) {
            currentPosition = value;
            setState(() {});
          },
          waveform: widget.waveformData,
          height: 120,
          style: WaveformStyle(
            waveColor: Colors.greenAccent,
            secondaryWaveColor: Colors.green,
            backgroundColor: Colors.grey.shade900,
            barWidth: 3.0,
            barSpacing: 1.0,
            minBarHeight: 2.0,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        if (widget.waveformData.isStereo) ...[
          const SizedBox(height: 8),
          const Text(
            'Left Channel (top) / Right Channel (bottom)',
            style: TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _ExtractionProgressIndicator extends StatelessWidget {
  const _ExtractionProgressIndicator({
    required this.taskId,
    required this.isExtracting,
  });

  final String taskId;
  final bool isExtracting;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProgressModel>(
      stream: ProVideoEditor.instance.progressStreamById(taskId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !isExtracting) {
          return const SizedBox.shrink();
        }

        final progress = snapshot.data!.progress;
        return SizedBox(
          width: 50,
          child: Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }
}
