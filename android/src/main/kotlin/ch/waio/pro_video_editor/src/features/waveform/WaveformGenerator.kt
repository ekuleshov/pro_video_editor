package ch.waio.pro_video_editor.src.features.waveform

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import ch.waio.pro_video_editor.src.features.audio.NoAudioTrackException
import ch.waio.pro_video_editor.src.features.waveform.models.WaveformConfig
import ch.waio.pro_video_editor.src.features.waveform.models.WaveformJobHandle
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max

/**
 * Service for generating waveform data from video/audio files.
 *
 * This class handles the waveform generation pipeline using Android MediaCodec:
 * - Extracts and decodes audio track to PCM
 * - Computes peak amplitudes per time block
 * - Supports stereo and mono audio
 * - Provides progress tracking during generation
 * - Supports cancellation of active jobs
 *
 * Architecture:
 * - Uses MediaExtractor to demux audio track
 * - Uses MediaCodec for hardware-accelerated decoding to PCM
 * - Computes peaks in streaming fashion (constant memory usage)
 * - Returns normalized float arrays to Flutter
 */
class WaveformGenerator(private val context: Context) {

    companion object {
        private const val TAG = "WaveformGenerator"
        private const val TIMEOUT_US = 10000L
    }

    /**
     * Generates waveform data from a video file asynchronously.
     *
     * @param config Complete waveform configuration
     * @param onProgress Callback invoked with progress updates (0.0 to 1.0)
     * @param onComplete Callback invoked on success with waveform data map
     * @param onError Callback invoked if generation fails
     * @return WaveformJobHandle for cancellation
     */
    fun generate(
        config: WaveformConfig,
        onProgress: (Double) -> Unit,
        onComplete: (Map<String, Any?>) -> Unit,
        onError: (Throwable) -> Unit
    ): WaveformJobHandle {
        val shouldStop = AtomicBoolean(false)
        val mainHandler = Handler(Looper.getMainLooper())

        Thread {
            var extractor: MediaExtractor? = null
            var decoder: MediaCodec? = null

            try {
                // Initialize extractor
                extractor = MediaExtractor()
                extractor.setDataSource(config.inputPath)

                // Find audio track
                val audioTrackIndex = findAudioTrack(extractor)
                if (audioTrackIndex < 0) {
                    throw NoAudioTrackException("No audio track found in video file")
                }

                extractor.selectTrack(audioTrackIndex)
                val format = extractor.getTrackFormat(audioTrackIndex)

                // Extract audio properties
                val mime = format.getString(MediaFormat.KEY_MIME)
                    ?: throw IllegalArgumentException("No MIME type found")
                val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val durationUs = format.getLong(MediaFormat.KEY_DURATION)

                // Calculate time range
                val startUs = config.startUs ?: 0L
                val endUs = config.endUs ?: durationUs
                val actualDurationUs = endUs - startUs
                val durationMs = (actualDurationUs / 1000).toInt()

                // Calculate samples needed
                val totalSamples = ((actualDurationUs / 1_000_000.0) * config.samplesPerSecond).toInt()
                    .coerceAtLeast(1)
                
                // Samples per waveform point (PCM samples to average)
                val samplesPerBlock = (sampleRate.toDouble() / config.samplesPerSecond).toInt()
                    .coerceAtLeast(1)

                // Prepare output arrays
                val leftPeaks = FloatArray(totalSamples)
                val rightPeaks = if (channelCount >= 2) FloatArray(totalSamples) else null

                // Seek to start if needed
                if (startUs > 0) {
                    extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                }

                // Create decoder
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(format, null, null, 0)
                decoder.start()

                val bufferInfo = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                var currentSampleIndex = 0
                var accumulatedLeftPeak = 0f
                var accumulatedRightPeak = 0f
                var samplesInCurrentBlock = 0
                var totalDecodedSamples = 0L
                val expectedTotalSamples = (actualDurationUs * sampleRate / 1_000_000).toLong()

                mainHandler.post { onProgress(0.0) }

                while (!outputDone && !shouldStop.get()) {
                    // Feed input
                    if (!inputDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                            if (inputBuffer != null) {
                                val sampleSize = extractor.readSampleData(inputBuffer, 0)
                                if (sampleSize < 0) {
                                    decoder.queueInputBuffer(
                                        inputBufferIndex, 0, 0, 0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                    )
                                    inputDone = true
                                } else {
                                    val presentationTimeUs = extractor.sampleTime
                                    
                                    // Check if we've passed the end time
                                    if (presentationTimeUs > endUs) {
                                        decoder.queueInputBuffer(
                                            inputBufferIndex, 0, 0, 0,
                                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                        )
                                        inputDone = true
                                    } else {
                                        decoder.queueInputBuffer(
                                            inputBufferIndex, 0, sampleSize,
                                            presentationTimeUs, 0
                                        )
                                        extractor.advance()
                                    }
                                }
                            }
                        }
                    }

                    // Process output
                    val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                    when {
                        outputBufferIndex >= 0 -> {
                            val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                            if (outputBuffer != null && bufferInfo.size > 0) {
                                // Process PCM data
                                outputBuffer.order(ByteOrder.nativeOrder())
                                val pcmData = ShortArray(bufferInfo.size / 2)
                                outputBuffer.asShortBuffer().get(pcmData)

                                // Process samples and compute peaks
                                var i = 0
                                while (i < pcmData.size && currentSampleIndex < totalSamples) {
                                    // Read left channel
                                    val leftSample = abs(pcmData[i].toFloat() / Short.MAX_VALUE)
                                    accumulatedLeftPeak = max(accumulatedLeftPeak, leftSample)

                                    // Read right channel if stereo
                                    if (channelCount >= 2 && i + 1 < pcmData.size) {
                                        val rightSample = abs(pcmData[i + 1].toFloat() / Short.MAX_VALUE)
                                        accumulatedRightPeak = max(accumulatedRightPeak, rightSample)
                                        i += 2
                                    } else {
                                        i += 1
                                    }

                                    samplesInCurrentBlock++
                                    totalDecodedSamples++

                                    // Emit peak when block is complete
                                    if (samplesInCurrentBlock >= samplesPerBlock) {
                                        if (currentSampleIndex < totalSamples) {
                                            leftPeaks[currentSampleIndex] = accumulatedLeftPeak
                                            rightPeaks?.set(currentSampleIndex, accumulatedRightPeak)
                                            currentSampleIndex++
                                        }
                                        accumulatedLeftPeak = 0f
                                        accumulatedRightPeak = 0f
                                        samplesInCurrentBlock = 0

                                        // Update progress periodically
                                        if (currentSampleIndex % 100 == 0) {
                                            val progress = currentSampleIndex.toDouble() / totalSamples
                                            mainHandler.post { onProgress(progress.coerceIn(0.0, 1.0)) }
                                        }
                                    }
                                }
                            }

                            decoder.releaseOutputBuffer(outputBufferIndex, false)

                            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                outputDone = true
                            }
                        }
                        outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            // Format changed, continue processing
                            Log.d(TAG, "Output format changed")
                        }
                    }
                }

                // Handle remaining samples
                if (samplesInCurrentBlock > 0 && currentSampleIndex < totalSamples) {
                    leftPeaks[currentSampleIndex] = accumulatedLeftPeak
                    rightPeaks?.set(currentSampleIndex, accumulatedRightPeak)
                    currentSampleIndex++
                }

                // Check cancellation
                if (shouldStop.get()) {
                    throw InterruptedException("Waveform generation cancelled by user")
                }

                // Trim arrays to actual size if needed
                val finalLeftPeaks = if (currentSampleIndex < totalSamples) {
                    leftPeaks.copyOf(currentSampleIndex)
                } else {
                    leftPeaks
                }

                val finalRightPeaks = rightPeaks?.let { peaks ->
                    if (currentSampleIndex < totalSamples) {
                        peaks.copyOf(currentSampleIndex)
                    } else {
                        peaks
                    }
                }

                // Build result map
                val result = mutableMapOf<String, Any?>(
                    "leftChannel" to finalLeftPeaks.toList(),
                    "sampleRate" to sampleRate,
                    "duration" to durationMs,
                    "samplesPerSecond" to config.samplesPerSecond
                )

                if (finalRightPeaks != null) {
                    result["rightChannel"] = finalRightPeaks.toList()
                }

                mainHandler.post {
                    onProgress(1.0)
                    onComplete(result)
                }

            } catch (e: Exception) {
                Log.e(TAG, "Error generating waveform: ${e.message}", e)
                mainHandler.post { onError(e) }
            } finally {
                try {
                    decoder?.stop()
                    decoder?.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing decoder: ${e.message}")
                }
                try {
                    extractor?.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing extractor: ${e.message}")
                }
            }
        }.start()

        return WaveformJobHandle {
            shouldStop.set(true)
        }
    }

    /**
     * Finds the first audio track in the media file.
     *
     * @return Track index if found, -1 otherwise
     */
    private fun findAudioTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                return i
            }
        }
        return -1
    }
}
