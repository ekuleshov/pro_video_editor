package ch.waio.pro_video_editor.src.features.render.helpers

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

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
        val overallStartTime = System.currentTimeMillis()
        Log.d(TAG, "🎵 Starting audio mixing")
        Log.d(TAG, "Video: $videoPath (volume: $videoVolume)")
        Log.d(TAG, "Custom: $customAudioPath (volume: $customVolume)")
        Log.d(TAG, "Target duration: ${targetDuration}ms")
        
        // Create output file
        val outputFile = File(context.cacheDir, "mixed_audio_${System.currentTimeMillis()}.mp4")
        val outputPath = outputFile.absolutePath
        
        // Fast-Path: Check if we can avoid decode/encode cycle
        if (videoVolume == 0f) {
            Log.d(TAG, "⚡ FAST PATH: Only custom audio (videoVolume=0), extracting directly...")
            val result = extractAudioTrackDirect(customAudioPath, outputPath, targetDuration)
            val totalTime = System.currentTimeMillis() - overallStartTime
            Log.d(TAG, "✅ Fast path completed in ${totalTime}ms (saved ~${9000-totalTime}ms!)")
            onProgress?.invoke(1.0)
            return result
        }
        
        if (customVolume == 0f) {
            Log.d(TAG, "⚡ FAST PATH: Only video audio (customVolume=0), extracting directly...")
            val result = extractAudioTrackDirect(videoPath, outputPath, targetDuration)
            val totalTime = System.currentTimeMillis() - overallStartTime
            Log.d(TAG, "✅ Fast path completed in ${totalTime}ms (saved ~${9000-totalTime}ms!)")
            onProgress?.invoke(1.0)
            return result
        }

        // Use video audio format as the base format
        val videoFormat = getAudioFormat(videoPath)
            ?: throw IllegalArgumentException("No audio track in video file")
        
        val videoSampleRate = videoFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val videoChannelCount = videoFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        
        Log.d(TAG, "Video audio format: ${videoSampleRate}Hz, $videoChannelCount channels")
        Log.d(TAG, "🐢 SLOW PATH: Full decode/mix/encode required (both volumes > 0)")
        
        // Extract and decode both audio tracks in parallel (0-40% of progress)
        Log.d(TAG, "⏱️ [TIMING] Starting parallel audio decoding...")
        val decodingStartTime = System.currentTimeMillis()
        val (videoAudioData, customAudioData) = runBlocking {
            val videoJob = async(Dispatchers.Default) {
                extractAndDecodeAudio(videoPath, targetDuration) { progress ->
                    onProgress?.invoke(progress * 0.20) // 0-20%
                }
            }
            
            val customJob = async(Dispatchers.Default) {
                extractAndDecodeAudio(customAudioPath, targetDuration) { progress ->
                    onProgress?.invoke(0.20 + progress * 0.20) // 20-40%
                }
            }
            
            Pair(videoJob.await(), customJob.await())
        }
        val decodingEndTime = System.currentTimeMillis()
        val decodingDuration = decodingEndTime - decodingStartTime
        Log.d(TAG, "✅ [TIMING] Audio decoding completed in ${decodingDuration}ms")
        Log.d(TAG, "   - Video: ${videoAudioData.pcmData.size} samples, ${videoAudioData.sampleRate}Hz, ${videoAudioData.channelCount}ch")
        Log.d(TAG, "   - Custom: ${customAudioData.pcmData.size} samples, ${customAudioData.sampleRate}Hz, ${customAudioData.channelCount}ch")
        
        // Resample custom audio if needed (40-50%)
        val resamplingStartTime = System.currentTimeMillis()
        val resampledCustomData = if (customAudioData.sampleRate != videoSampleRate) {
            Log.d(TAG, "⏱️ [TIMING] Starting resampling: ${customAudioData.sampleRate}Hz → ${videoSampleRate}Hz")
            val result = resamplePCM(customAudioData.pcmData, customAudioData.sampleRate, videoSampleRate)
            val resamplingEndTime = System.currentTimeMillis()
            Log.d(TAG, "✅ [TIMING] Resampling completed in ${resamplingEndTime - resamplingStartTime}ms (${customAudioData.pcmData.size} → ${result.size} samples)")
            result
        } else {
            Log.d(TAG, "⏭️ [TIMING] Skipping resampling (same rate: ${videoSampleRate}Hz)")
            customAudioData.pcmData
        }
        onProgress?.invoke(0.50)
        
        // Mix the audio data with volume adjustment (50-60%)
        Log.d(TAG, "⏱️ [TIMING] Starting audio mixing...")
        val mixingStartTime = System.currentTimeMillis()
        val mixedPCM = mixPCMAudio(
            videoAudioData.pcmData,
            videoAudioData.channelCount,
            resampledCustomData,
            customAudioData.channelCount,
            videoChannelCount,
            videoVolume,
            customVolume
        )
        val mixingEndTime = System.currentTimeMillis()
        val mixingDuration = mixingEndTime - mixingStartTime
        Log.d(TAG, "✅ [TIMING] Audio mixing completed in ${mixingDuration}ms (${mixedPCM.size} samples)")
        onProgress?.invoke(0.60)
        
        // Encode mixed PCM to AAC and mux (60-100%)
        Log.d(TAG, "⏱️ [TIMING] Starting audio encoding...")
        val encodingStartTime = System.currentTimeMillis()
        encodeMixedAudio(mixedPCM, videoSampleRate, videoChannelCount, outputPath) { encProgress ->
            onProgress?.invoke(0.60 + encProgress * 0.40)
        }
        val encodingEndTime = System.currentTimeMillis()
        val encodingDuration = encodingEndTime - encodingStartTime
        Log.d(TAG, "✅ [TIMING] Audio encoding completed in ${encodingDuration}ms")
        
        onProgress?.invoke(1.0)
        
        val overallEndTime = System.currentTimeMillis()
        val overallDuration = overallEndTime - overallStartTime
        Log.d(TAG, "")
        Log.d(TAG, "📊 [TIMING SUMMARY]")
        Log.d(TAG, "  Total:     ${overallDuration}ms")
        Log.d(TAG, "  Decoding:  ${decodingDuration}ms (${(decodingDuration * 100.0 / overallDuration).toInt()}%)")
        Log.d(TAG, "  Mixing:    ${mixingDuration}ms (${(mixingDuration * 100.0 / overallDuration).toInt()}%)")
        Log.d(TAG, "  Encoding:  ${encodingDuration}ms (${(encodingDuration * 100.0 / overallDuration).toInt()}%)")
        Log.d(TAG, "✅ Audio mixed successfully: $outputPath")
        Log.d(TAG, "")
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
     * Fast path: Extract audio track directly without decode/encode.
     * Uses MediaMuxer to copy compressed audio track as-is.
     * ~100x faster than decode/encode cycle.
     */
    private fun extractAudioTrackDirect(
        inputPath: String,
        outputPath: String,
        maxDurationMs: Long
    ): String {
        val startTime = System.currentTimeMillis()
        
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)
        
        // Find audio track
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
            throw IllegalArgumentException("No audio track found in $inputPath")
        }
        
        extractor.selectTrack(audioTrackIndex)
        
        // Setup muxer
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val muxerTrackIndex = muxer.addTrack(audioFormat)
        muxer.start()
        
        // Copy audio samples directly
        val bufferInfo = MediaCodec.BufferInfo()
        val buffer = ByteBuffer.allocate(1024 * 1024) // 1MB buffer
        val maxDurationUs = maxDurationMs * 1000
        var samplesWritten = 0
        
        while (true) {
            val sampleSize = extractor.readSampleData(buffer, 0)
            
            if (sampleSize < 0) {
                break // End of stream
            }
            
            val presentationTimeUs = extractor.sampleTime
            
            // Stop if we've reached max duration
            if (presentationTimeUs > maxDurationUs) {
                Log.d(TAG, "Reached max duration: ${presentationTimeUs / 1000}ms > ${maxDurationMs}ms")
                break
            }
            
            bufferInfo.offset = 0
            bufferInfo.size = sampleSize
            bufferInfo.presentationTimeUs = presentationTimeUs
            bufferInfo.flags = extractor.sampleFlags
            
            muxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)
            samplesWritten++
            
            extractor.advance()
        }
        
        muxer.stop()
        muxer.release()
        extractor.release()
        
        val endTime = System.currentTimeMillis()
        val duration = endTime - startTime
        Log.d(TAG, "   ➡️ Copied $samplesWritten audio samples directly in ${duration}ms")
        
        return outputPath
    }

    /**
     * Extract and decode audio to raw PCM data.
     * Volume adjustment is now done during mixing for better performance.
     */
    private fun extractAndDecodeAudio(
        filePath: String,
        targetDuration: Long,
        onProgress: ((Double) -> Unit)? = null
    ): AudioData {
        val startTime = System.currentTimeMillis()
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
        
        // Pre-allocate PCM array based on estimated size
        val estimatedSamples = ((durationUs / 1000000.0) * sampleRate * channelCount * 1.1).toInt()
        var pcmData = ShortArray(estimatedSamples)
        var pcmIndex = 0
        
        // Create decoder
        val mime = audioFormat.getString(MediaFormat.KEY_MIME)!!
        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(audioFormat, null, null, 0)
        decoder.start()
        
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
                    // Direct batch copy without volume adjustment (much faster)
                    outputBuffer.position(bufferInfo.offset)
                    outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                    outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
                    
                    val shortBuffer = outputBuffer.asShortBuffer()
                    val samplesInBuffer = shortBuffer.remaining()
                    
                    // Ensure capacity
                    if (pcmIndex + samplesInBuffer > pcmData.size) {
                        val newSize = maxOf(pcmData.size * 2, pcmIndex + samplesInBuffer)
                        pcmData = pcmData.copyOf(newSize)
                    }
                    
                    // Fast batch copy
                    shortBuffer.get(pcmData, pcmIndex, samplesInBuffer)
                    pcmIndex += samplesInBuffer
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
        
        // Trim to actual size
        if (pcmIndex < pcmData.size) {
            pcmData = pcmData.copyOf(pcmIndex)
        }
        
        val endTime = System.currentTimeMillis()
        val duration = endTime - startTime
        Log.d(TAG, "   ➡️ Decoded ${pcmData.size} samples in ${duration}ms (${filePath.substringAfterLast('/')})")
        
        return AudioData(pcmData, sampleRate, channelCount)
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
     * Mix two PCM audio streams into one with volume adjustment.
     * Optimized for better cache locality and reduced bounds checking.
     * Volume is applied during mixing to avoid extra loops.
     */
    private fun mixPCMAudio(
        audio1: ShortArray,
        channels1: Int,
        audio2: ShortArray,
        channels2: Int,
        outputChannels: Int,
        volume1: Float,
        volume2: Float
    ): ShortArray {
        Log.d(TAG, "Mixing: ${audio1.size} samples ($channels1 ch) + ${audio2.size} samples ($channels2 ch) → $outputChannels ch")
        
        // Calculate frame counts (samples per channel)
        val frames1 = audio1.size / channels1
        val frames2 = audio2.size / channels2
        val maxFrames = maxOf(frames1, frames2)
        
        val output = ShortArray(maxFrames * outputChannels)
        
        // Optimize for common cases
        when {
            // Both mono to mono - fastest path
            channels1 == 1 && channels2 == 1 && outputChannels == 1 -> {
                val minFrames = minOf(frames1, frames2)
                for (i in 0 until minFrames) {
                    val sample1 = (audio1[i] * volume1).toInt()
                    val sample2 = (audio2[i] * volume2).toInt()
                    val mixed = sample1 + sample2
                    output[i] = mixed.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                }
                // Copy remaining samples with volume
                if (frames1 > minFrames) {
                    for (i in minFrames until frames1) {
                        output[i] = (audio1[i] * volume1).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    }
                } else if (frames2 > minFrames) {
                    for (i in minFrames until frames2) {
                        output[i] = (audio2[i] * volume2).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    }
                }
            }
            
            // Both stereo to stereo - second fastest
            channels1 == 2 && channels2 == 2 && outputChannels == 2 -> {
                val minFrames = minOf(frames1, frames2)
                for (i in 0 until minFrames) {
                    val idx = i * 2
                    // Left channel
                    val sample1L = (audio1[idx] * volume1).toInt()
                    val sample2L = (audio2[idx] * volume2).toInt()
                    output[idx] = (sample1L + sample2L).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    // Right channel
                    val sample1R = (audio1[idx + 1] * volume1).toInt()
                    val sample2R = (audio2[idx + 1] * volume2).toInt()
                    output[idx + 1] = (sample1R + sample2R).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                }
                // Copy remaining samples with volume
                val minSamples = minFrames * 2
                if (frames1 > minFrames) {
                    for (i in minSamples until frames1 * 2) {
                        output[i] = (audio1[i] * volume1).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    }
                } else if (frames2 > minFrames) {
                    for (i in minSamples until frames2 * 2) {
                        output[i] = (audio2[i] * volume2).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    }
                }
            }
            
            // General case with channel conversion
            else -> {
                for (frame in 0 until maxFrames) {
                    val outIdx = frame * outputChannels
                    
                    for (ch in 0 until outputChannels) {
                        var mixed = 0
                        
                        // Add from audio1 if available with volume
                        if (frame < frames1) {
                            val srcCh = if (channels1 == 1) 0 else min(ch, channels1 - 1)
                            mixed += (audio1[frame * channels1 + srcCh] * volume1).toInt()
                        }
                        
                        // Add from audio2 if available with volume
                        if (frame < frames2) {
                            val srcCh = if (channels2 == 1) 0 else min(ch, channels2 - 1)
                            mixed += (audio2[frame * channels2 + srcCh] * volume2).toInt()
                        }
                        
                        // Clamp to prevent overflow
                        output[outIdx + ch] = mixed.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    }
                }
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
                        // Use asShortBuffer for batch write (much faster)
                        inputBuffer.order(ByteOrder.LITTLE_ENDIAN)
                        val shortBuffer = inputBuffer.asShortBuffer()
                        shortBuffer.put(pcmData, pcmOffset, samplesToWrite)
                        inputBuffer.position(inputBuffer.position() + samplesToWrite * 2)
                        
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
