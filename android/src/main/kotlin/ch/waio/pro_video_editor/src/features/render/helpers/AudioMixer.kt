package ch.waio.pro_video_editor.src.features.render.helpers

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import kotlin.math.min

// TODO: Improve performance!

/**
 * Mixes two audio tracks (video original + custom audio) into a single track.
 * Handles different sample rates and channel counts while preserving quality.
 */
class AudioMixer(private val context: Context) {
    companion object {
        private const val TAG = "AudioMixer"
        private const val TIMEOUT_US = 10000L
    }

    /**
     * Mix video audio with custom audio track.
     * 
     * @param videoPath Path to video file with original audio
     * @param customAudioPath Path to custom audio file
     * @param videoVolume Volume multiplier for video audio (0.0 - 1.0)
     * @param customVolume Volume multiplier for custom audio (0.0 - 1.0)
     * @param targetDuration Target duration in milliseconds for looping custom audio
     * @param onProgress Optional callback for progress updates (0.0 to 1.0)
     * @return Path to mixed audio file
     */
    fun mixAudio(
        videoPath: String,
        customAudioPath: String,
        videoVolume: Float,
        customVolume: Float,
        targetDuration: Long,
        onProgress: ((Double) -> Unit)? = null
    ): String {
        Log.d(TAG, "🎵 Starting audio mixing")
        Log.d(TAG, "Video: $videoPath (volume: $videoVolume)")
        Log.d(TAG, "Custom: $customAudioPath (volume: $customVolume)")
        Log.d(TAG, "Target duration: ${targetDuration}ms")

        // Use video audio format as the base format
        val videoFormat = getAudioFormat(videoPath)
            ?: throw IllegalArgumentException("No audio track in video file")
        
        val videoSampleRate = videoFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val videoChannelCount = videoFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        
        Log.d(TAG, "Video audio format: ${videoSampleRate}Hz, $videoChannelCount channels")
        
        // Create output file
        val outputFile = File(context.cacheDir, "mixed_audio_${System.currentTimeMillis()}.mp4")
        val outputPath = outputFile.absolutePath
        
        // Extract and decode both audio tracks (0-40% of progress)
        val videoAudioData = extractAndDecodeAudio(videoPath, videoVolume, targetDuration) { progress ->
            onProgress?.invoke(progress * 0.20) // 0-20%
        }
        
        val customAudioData = extractAndDecodeAudio(customAudioPath, customVolume, targetDuration) { progress ->
            onProgress?.invoke(0.20 + progress * 0.20) // 20-40%
        }
        
        // Resample custom audio if needed (40-50%)
        val resampledCustomData = if (customAudioData.sampleRate != videoSampleRate) {
            Log.d(TAG, "Resampling custom audio: ${customAudioData.sampleRate}Hz → ${videoSampleRate}Hz")
            resamplePCM(customAudioData.pcmData, customAudioData.sampleRate, videoSampleRate)
        } else {
            customAudioData.pcmData
        }
        onProgress?.invoke(0.50)
        
        // Mix the audio data (50-60%)
        val mixedPCM = mixPCMAudio(
            videoAudioData.pcmData,
            videoAudioData.channelCount,
            resampledCustomData,
            customAudioData.channelCount,
            videoChannelCount
        )
        onProgress?.invoke(0.60)
        
        // Encode mixed PCM to AAC and mux (60-100%)
        encodeMixedAudio(mixedPCM, videoSampleRate, videoChannelCount, outputPath) { encProgress ->
            onProgress?.invoke(0.60 + encProgress * 0.40)
        }
        
        onProgress?.invoke(1.0)
        Log.d(TAG, "✅ Audio mixed successfully: $outputPath")
        return outputPath
    }

    /**
     * Extract audio format from media file.
     */
    private fun getAudioFormat(filePath: String): MediaFormat? {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(filePath)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) {
                    return format
                }
            }
        } finally {
            extractor.release()
        }
        return null
    }

    /**
     * Extract and decode audio to raw PCM data.
     */
    private fun extractAndDecodeAudio(
        filePath: String,
        volumeMultiplier: Float,
        targetDuration: Long,
        onProgress: ((Double) -> Unit)? = null
    ): AudioData {
        val extractor = MediaExtractor()
        extractor.setDataSource(filePath)
        
        var audioTrackIndex = -1
        var audioFormat: MediaFormat? = null
        
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith("audio/") == true) {
                audioTrackIndex = i
                audioFormat = format
                break
            }
        }
        
        if (audioTrackIndex == -1 || audioFormat == null) {
            extractor.release()
            throw IllegalArgumentException("No audio track found in $filePath")
        }
        
        extractor.selectTrack(audioTrackIndex)
        
        val sampleRate = audioFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = audioFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val durationUs = if (audioFormat.containsKey(MediaFormat.KEY_DURATION)) {
            audioFormat.getLong(MediaFormat.KEY_DURATION)
        } else {
            targetDuration * 1000L
        }
        
        Log.d(TAG, "Decoding audio: ${sampleRate}Hz, $channelCount ch, ${durationUs / 1000}ms")
        
        // Create decoder
        val mime = audioFormat.getString(MediaFormat.KEY_MIME)!!
        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(audioFormat, null, null, 0)
        decoder.start()
        
        val pcmData = mutableListOf<Short>()
        var inputDone = false
        var outputDone = false
        var lastProgressReport = 0L
        
        val bufferInfo = MediaCodec.BufferInfo()
        
        while (!outputDone) {
            // Feed input
            if (!inputDone) {
                val inputBufferId = decoder.dequeueInputBuffer(TIMEOUT_US)
                if (inputBufferId >= 0) {
                    val inputBuffer = decoder.getInputBuffer(inputBufferId)!!
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(inputBufferId, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        val presentationTime = extractor.sampleTime
                        decoder.queueInputBuffer(inputBufferId, 0, sampleSize, presentationTime, 0)
                        extractor.advance()
                        
                        // Report progress based on timestamp (limit to once per 100ms)
                        if (durationUs > 0 && onProgress != null && System.currentTimeMillis() - lastProgressReport > 100) {
                            val progress = (presentationTime.toDouble() / durationUs.toDouble()).coerceIn(0.0, 1.0)
                            onProgress(progress)
                            lastProgressReport = System.currentTimeMillis()
                        }
                    }
                }
            }
            
            // Get output
            val outputBufferId = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            if (outputBufferId >= 0) {
                val outputBuffer = decoder.getOutputBuffer(outputBufferId)!!
                
                if (bufferInfo.size > 0) {
                    // Convert PCM bytes to shorts and apply volume
                    outputBuffer.position(bufferInfo.offset)
                    outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                    
                    while (outputBuffer.remaining() >= 2) {
                        val sample = outputBuffer.short
                        val adjustedSample = (sample * volumeMultiplier).toInt()
                        pcmData.add(adjustedSample.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort())
                    }
                }
                
                decoder.releaseOutputBuffer(outputBufferId, false)
                
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    outputDone = true
                }
            }
        }
        
        decoder.stop()
        decoder.release()
        extractor.release()
        
        Log.d(TAG, "Decoded ${pcmData.size} PCM samples")
        
        return AudioData(pcmData.toShortArray(), sampleRate, channelCount)
    }

    /**
     * Simple linear resampling for PCM data.
     */
    private fun resamplePCM(input: ShortArray, fromRate: Int, toRate: Int): ShortArray {
        if (fromRate == toRate) return input
        
        val ratio = toRate.toDouble() / fromRate.toDouble()
        val outputSize = (input.size * ratio).toInt()
        val output = ShortArray(outputSize)
        
        for (i in output.indices) {
            val srcIndex = i / ratio
            val index = srcIndex.toInt()
            
            if (index < input.size - 1) {
                // Linear interpolation
                val fraction = srcIndex - index
                val sample1 = input[index].toDouble()
                val sample2 = input[index + 1].toDouble()
                output[i] = (sample1 + (sample2 - sample1) * fraction).toInt().toShort()
            } else if (index < input.size) {
                output[i] = input[index]
            }
        }
        
        return output
    }

    /**
     * Mix two PCM audio streams into one.
     */
    private fun mixPCMAudio(
        audio1: ShortArray,
        channels1: Int,
        audio2: ShortArray,
        channels2: Int,
        outputChannels: Int
    ): ShortArray {
        Log.d(TAG, "Mixing: ${audio1.size} samples ($channels1 ch) + ${audio2.size} samples ($channels2 ch) → $outputChannels ch")
        
        // Calculate frame counts (samples per channel)
        val frames1 = audio1.size / channels1
        val frames2 = audio2.size / channels2
        val maxFrames = maxOf(frames1, frames2)
        
        val output = ShortArray(maxFrames * outputChannels)
        
        for (frame in 0 until maxFrames) {
            for (ch in 0 until outputChannels) {
                var mixed = 0
                
                // Add from audio1 if available
                if (frame < frames1) {
                    val srcCh = if (channels1 == 1) 0 else min(ch, channels1 - 1)
                    mixed += audio1[frame * channels1 + srcCh]
                }
                
                // Add from audio2 if available
                if (frame < frames2) {
                    val srcCh = if (channels2 == 1) 0 else min(ch, channels2 - 1)
                    mixed += audio2[frame * channels2 + srcCh]
                }
                
                // Clamp to prevent overflow
                output[frame * outputChannels + ch] = mixed.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }
        }
        
        Log.d(TAG, "Mixed ${output.size} output samples")
        return output
    }

    /**
     * Encode mixed PCM audio to AAC and save to file.
     */
    private fun encodeMixedAudio(
        pcmData: ShortArray,
        sampleRate: Int,
        channelCount: Int,
        outputPath: String,
        onProgress: ((Double) -> Unit)? = null
    ) {
        Log.d(TAG, "Encoding mixed audio: ${sampleRate}Hz, $channelCount ch, ${pcmData.size} samples")
        
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount)
        format.setInteger(MediaFormat.KEY_BIT_RATE, 131072) // 128 kbps
        format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()
        
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var trackIndex = -1
        var muxerStarted = false
        
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        var pcmOffset = 0
        var presentationTimeUs = 0L
        var lastProgressReport = 0L
        
        while (!outputDone) {
            // Feed input
            if (!inputDone) {
                val inputBufferId = encoder.dequeueInputBuffer(TIMEOUT_US)
                if (inputBufferId >= 0) {
                    val inputBuffer = encoder.getInputBuffer(inputBufferId)!!
                    inputBuffer.clear()
                    
                    val samplesToWrite = min((inputBuffer.remaining() / 2), pcmData.size - pcmOffset)
                    
                    if (samplesToWrite > 0) {
                        for (i in 0 until samplesToWrite) {
                            inputBuffer.putShort(pcmData[pcmOffset + i])
                        }
                        
                        val flags = if (pcmOffset + samplesToWrite >= pcmData.size) {
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        } else {
                            0
                        }
                        
                        encoder.queueInputBuffer(inputBufferId, 0, samplesToWrite * 2, presentationTimeUs, flags)
                        pcmOffset += samplesToWrite
                        
                        // Report encoding progress (limit to once per 100ms)
                        if (onProgress != null && System.currentTimeMillis() - lastProgressReport > 100) {
                            val progress = (pcmOffset.toDouble() / pcmData.size.toDouble()).coerceIn(0.0, 1.0)
                            onProgress(progress)
                            lastProgressReport = System.currentTimeMillis()
                        }
                        
                        // Calculate presentation time for next frame
                        presentationTimeUs += (samplesToWrite * 1000000L) / (sampleRate * channelCount)
                        
                        if (flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            inputDone = true
                            Log.d(TAG, "All PCM data queued: $pcmOffset samples")
                        }
                    } else if (pcmOffset >= pcmData.size) {
                        // No more data to write
                        encoder.queueInputBuffer(inputBufferId, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                        Log.d(TAG, "EOS sent to encoder")
                    }
                }
            }
            
            // Get output
            val outputBufferId = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            when {
                outputBufferId == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val outputFormat = encoder.outputFormat
                    trackIndex = muxer.addTrack(outputFormat)
                    muxer.start()
                    muxerStarted = true
                    Log.d(TAG, "Muxer started with track index: $trackIndex")
                }
                outputBufferId >= 0 -> {
                    val outputBuffer = encoder.getOutputBuffer(outputBufferId)!!
                    
                    if (bufferInfo.size > 0 && muxerStarted) {
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                    }
                    
                    encoder.releaseOutputBuffer(outputBufferId, false)
                    
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true
                    }
                }
            }
        }
        
        encoder.stop()
        encoder.release()
        muxer.stop()
        muxer.release()
        
        Log.d(TAG, "Encoding complete: $outputPath")
    }

    /**
     * Data class to hold decoded audio information.
     */
    private data class AudioData(
        val pcmData: ShortArray,
        val sampleRate: Int,
        val channelCount: Int
    )
}
