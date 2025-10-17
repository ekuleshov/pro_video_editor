import RENDER_TAG
import android.net.Uri
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.mp4.Mp4Extractor
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import applyCrop
import applyImageLayer
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteBuffer
import androidx.media3.common.audio.BaseAudioProcessor

data class VideoClip(
    val inputPath: String,
    val startUs: Long?,
    val endUs: Long?
)

/**
 * Custom AudioProcessor to adjust volume
 * Processes 16-bit PCM audio samples by multiplying each sample with the volume multiplier
 */
@UnstableApi
class VolumeAudioProcessor(private val volumeMultiplier: Float) : BaseAudioProcessor() {
    
    init {
        Log.d(RENDER_TAG, "VolumeAudioProcessor created with multiplier: $volumeMultiplier")
    }
    
    override fun onConfigure(inputAudioFormat: androidx.media3.common.audio.AudioProcessor.AudioFormat): androidx.media3.common.audio.AudioProcessor.AudioFormat {
        Log.d(RENDER_TAG, "VolumeAudioProcessor.onConfigure: sampleRate=${inputAudioFormat.sampleRate}, channels=${inputAudioFormat.channelCount}, encoding=${inputAudioFormat.encoding}")
        // Return the same format - we don't change the audio format, just the amplitude
        return inputAudioFormat
    }
    
    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) {
            return
        }
        
        // Get output buffer with same size as input
        val outputBuffer = replaceOutputBuffer(remaining)
        
        // Process 16-bit PCM samples
        val sampleCount = remaining / 2
        
        for (i in 0 until sampleCount) {
            // Read 16-bit sample
            val sample = inputBuffer.short
            
            // Apply volume multiplier
            val adjusted = (sample * volumeMultiplier).toInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            
            // Write adjusted sample
            outputBuffer.putShort(adjusted.toShort())
        }
        
        // Prepare output buffer for reading
        outputBuffer.flip()
        
        if (sampleCount <= 10) {
            Log.v(RENDER_TAG, "VolumeAudioProcessor: processed $sampleCount samples with volume ${volumeMultiplier}x")
        }
    }
}

@UnstableApi
fun applyComposition(
    videoClips: List<VideoClip>,
    videoEffects: List<Effect>,
    audioEffects: List<AudioProcessor>,
    enableAudio: Boolean,
    imageBytes: ByteArray?,
    rotationDegrees: Float,
    flipX: Boolean,
    flipY: Boolean,
    cropWidth: Int?,
    cropHeight: Int?,
    cropX: Int?,
    cropY: Int?,
    scaleX: Float?,
    scaleY: Float?,
    customAudioPath: String? = null,
    originalAudioVolume: Float? = null,
    customAudioVolume: Float? = null
): Composition? {
    if (videoClips.isEmpty()) {
        return null
    }

    Log.d(RENDER_TAG, "Creating composition with ${videoClips.size} video clips")
    Log.d(RENDER_TAG, "Audio enabled: $enableAudio")
    
    // Check if audio normalization is needed by detecting channel counts
    val audioChannelCounts = if (enableAudio && videoClips.size > 1) {
        videoClips.mapNotNull { clip ->
            try {
                val extractor = MediaExtractor()
                extractor.setDataSource(clip.inputPath)
                var channelCount: Int? = null
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        Log.d(RENDER_TAG, "Clip ${clip.inputPath}: $channelCount audio channels")
                        break
                    }
                }
                extractor.release()
                channelCount
            } catch (e: Exception) {
                Log.e(RENDER_TAG, "Failed to detect audio channels for ${clip.inputPath}: ${e.message}")
                null
            }
        }
    } else {
        emptyList()
    }
    
    // Determine if normalization is needed
    val needsNormalization = audioChannelCounts.isNotEmpty() && 
                             audioChannelCounts.toSet().size > 1
    
    if (needsNormalization) {
        Log.d(RENDER_TAG, "Audio normalization needed - detected different channel counts: $audioChannelCounts")
    } else if (audioChannelCounts.isNotEmpty()) {
        Log.d(RENDER_TAG, "Audio normalization NOT needed - all videos have same channel count: ${audioChannelCounts.firstOrNull()}")
    }
    
    // When concatenating multiple videos with audio, normalize to stereo (2 channels)
    // to avoid "AudioGraphInput reconfiguration" errors when videos have different channel counts
    val normalizedAudioEffects = if (needsNormalization) {
        Log.d(RENDER_TAG, "Adding ChannelMixingAudioProcessor to normalize audio to stereo")
        val channelMixer = ChannelMixingAudioProcessor()
        
        // 5.1 Surround (6 channels) to Stereo (2 channels)
        // Channels: FL, FR, FC, LFE, BL, BR -> L, R
        // Simple downmix: L = FL + 0.7*FC + 0.7*BL, R = FR + 0.7*FC + 0.7*BR
        val sixToTwo = floatArrayOf(
            1.0f, 0.0f, 0.7f, 0.0f, 0.7f, 0.0f,  // Left output
            0.0f, 1.0f, 0.7f, 0.0f, 0.0f, 0.7f   // Right output
        )
        channelMixer.putChannelMixingMatrix(
            ChannelMixingMatrix(/* inputChannelCount= */ 6, /* outputChannelCount= */ 2, sixToTwo)
        )
        
        // Stereo (2 channels) to Stereo (2 channels) - passthrough
        channelMixer.putChannelMixingMatrix(
            ChannelMixingMatrix.create(/* inputChannelCount= */ 2, /* outputChannelCount= */ 2)
        )
        
        // Mono (1 channel) to Stereo (2 channels)
        channelMixer.putChannelMixingMatrix(
            ChannelMixingMatrix.create(/* inputChannelCount= */ 1, /* outputChannelCount= */ 2)
        )
        
        mutableListOf<AudioProcessor>(channelMixer).apply { addAll(audioEffects) }
    } else {
        audioEffects
    }

    val editedMediaItems = videoClips.mapIndexed { index, clip ->
        Log.d(RENDER_TAG, "Processing clip $index: ${clip.inputPath}")
        val inputFile = File(clip.inputPath)
        
        if (!inputFile.exists()) {
            Log.e(RENDER_TAG, "ERROR: Video file does not exist: ${clip.inputPath}")
        } else {
            Log.d(RENDER_TAG, "Video file exists, size: ${inputFile.length()} bytes")
        }
        
        val mediaItemBuilder = MediaItem.Builder().setUri(Uri.fromFile(inputFile))

        if (clip.startUs != null || clip.endUs != null) {
            val startMs = (clip.startUs ?: 0L) / 1000
            val endMs = clip.endUs?.div(1000) ?: C.TIME_END_OF_SOURCE
            
            Log.d(RENDER_TAG, "Applying trim to clip ${clip.inputPath}: start=$startMs ms, end=$endMs ms")

            val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(startMs)
                .setEndPositionMs(endMs)
                .build()

            mediaItemBuilder.setClippingConfiguration(clippingConfig)
        }

        val mediaItem = mediaItemBuilder.build()
        
        val clipVideoEffects = mutableListOf<Effect>()
        
        clipVideoEffects.addAll(videoEffects)
        
        applyCrop(
            clipVideoEffects, inputFile, rotationDegrees,
            flipX, flipY, cropWidth, cropHeight, cropX, cropY
        )
        
        applyImageLayer(
            clipVideoEffects, inputFile, imageBytes, rotationDegrees,
            cropWidth, cropHeight, scaleX, scaleY
        )
        
        // Apply normalized audio effects to each clip
        // ChannelMixingAudioProcessor will convert all audio to stereo
        val clipAudioEffects = if (originalAudioVolume != null && originalAudioVolume != 1.0f) {
            // Add volume processor for original audio
            Log.d(RENDER_TAG, "Applying volume adjustment for clip $index: ${originalAudioVolume}x")
            val volumeProcessor = VolumeAudioProcessor(originalAudioVolume)
            mutableListOf<AudioProcessor>(volumeProcessor).apply { addAll(normalizedAudioEffects) }
        } else {
            Log.d(RENDER_TAG, "No volume adjustment for clip $index (volume: ${originalAudioVolume ?: 1.0f})")
            normalizedAudioEffects
        }
        
        val effects = Effects(clipAudioEffects, clipVideoEffects)
        
        val editedMediaItemBuilder = EditedMediaItem.Builder(mediaItem).setEffects(effects)

        // Remove audio from video if:
        // - Audio is disabled globally (!enableAudio)
        // - OR custom audio will completely replace it (originalAudioVolume == 0.0)
        val shouldRemoveAudio = !enableAudio || 
                                (customAudioPath != null && customAudioPath.isNotEmpty() && 
                                 originalAudioVolume != null && originalAudioVolume == 0.0f)
        
        if (shouldRemoveAudio) {
            Log.d(RENDER_TAG, "Removing audio from clip $index (enableAudio=$enableAudio, originalVolume=${originalAudioVolume ?: 1.0f})")
            editedMediaItemBuilder.setRemoveAudio(true)
        } else {
            Log.d(RENDER_TAG, "Keeping audio for clip $index (for mixing or normal playback)")
        }

        val builtItem = editedMediaItemBuilder.build()
        Log.d(RENDER_TAG, "Built EditedMediaItem $index with ${clipVideoEffects.size} video effects")
        builtItem
    }

    Log.d(RENDER_TAG, "Total EditedMediaItems created: ${editedMediaItems.size}")
    
    // Calculate total video duration for custom audio trimming
    var totalVideoDurationUs = 0L
    videoClips.forEach { clip ->
        val clipDurationUs = if (clip.endUs != null && clip.startUs != null) {
            clip.endUs - clip.startUs
        } else if (clip.endUs != null) {
            clip.endUs
        } else {
            // Get duration from video file
            try {
                val extractor = MediaExtractor()
                extractor.setDataSource(clip.inputPath)
                var duration = 0L
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("video/")) {
                        duration = format.getLong(MediaFormat.KEY_DURATION)
                        break
                    }
                }
                extractor.release()
                duration
            } catch (e: Exception) {
                Log.e(RENDER_TAG, "Failed to get video duration for ${clip.inputPath}: ${e.message}")
                0L
            }
        }
        totalVideoDurationUs += clipDurationUs
    }
    Log.d(RENDER_TAG, "Total video duration: ${totalVideoDurationUs / 1000} ms")
    
    // Detect if we need audio mixing (both original and custom audio)
    val needsAudioMixing = customAudioPath != null && customAudioPath.isNotEmpty() &&
                          originalAudioVolume != null && originalAudioVolume > 0.0f
    
    // Check custom audio sample rate BEFORE creating sequences
    var customAudioSampleRate = 0
    var forceRemoveOriginalAudio = false
    
    if (customAudioPath != null && customAudioPath.isNotEmpty()) {
        try {
            val extractor = MediaExtractor()
            extractor.setDataSource(customAudioPath)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    customAudioSampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    Log.d(RENDER_TAG, "Custom audio sample rate: $customAudioSampleRate Hz")
                    break
                }
            }
            extractor.release()
        } catch (e: Exception) {
            Log.e(RENDER_TAG, "Failed to detect custom audio sample rate: ${e.message}")
        }
        
        // Check if mixing is safe (same sample rate)
        val videoSampleRate = 48000 // Most videos use 48kHz
        val canMixSafely = customAudioSampleRate == videoSampleRate || customAudioSampleRate == 0
        
        if (needsAudioMixing && !canMixSafely) {
            Log.e(RENDER_TAG, "ERROR: Cannot mix audio with different sample rates!")
            Log.e(RENDER_TAG, "Video: ${videoSampleRate}Hz, Custom Audio: ${customAudioSampleRate}Hz")
            Log.e(RENDER_TAG, "WORKAROUND: Switching to REPLACE mode (removing original audio)")
            forceRemoveOriginalAudio = true
        } else if (needsAudioMixing) {
            Log.d(RENDER_TAG, "Audio mixing is safe - sample rates match or will be handled by Media3")
        }
    }
    
    // Rebuild video items if we need to force remove audio (sample rate mismatch)
    val finalVideoItems = if (forceRemoveOriginalAudio) {
        Log.w(RENDER_TAG, "Force removing original audio from all clips due to sample rate mismatch")
        editedMediaItems.map { item ->
            EditedMediaItem.Builder(item.mediaItem)
                .setEffects(item.effects) // Keep all effects (video + audio processors)
                .setRemoveAudio(true)     // But remove the actual audio stream
                .build()
        }
    } else {
        // Use original items as-is (they already have correct audio settings)
        editedMediaItems
    }
    
    // Build sequences - we need separate sequences for parallel playback
    val sequences = mutableListOf<EditedMediaItemSequence>()
    
    // Add video sequence
    val videoSequence = EditedMediaItemSequence(finalVideoItems)
    sequences.add(videoSequence)
    Log.d(RENDER_TAG, "Created video EditedMediaItemSequence with ${finalVideoItems.size} items")
    
    if (needsAudioMixing && !forceRemoveOriginalAudio) {
        Log.w(RENDER_TAG, "✅ Audio mixing ENABLED (original: ${originalAudioVolume}x, custom: ${customAudioVolume}x)")
        Log.w(RENDER_TAG, "✅ Sample rates are compatible - both audio tracks will be mixed")
    } else if (forceRemoveOriginalAudio) {
        Log.e(RENDER_TAG, "❌ Audio mixing DISABLED - sample rate mismatch detected")
        Log.e(RENDER_TAG, "❌ Only custom audio will be used (original audio removed)")
    }
    
    // Add custom audio track if provided as SEPARATE sequence for parallel playback
    if (customAudioPath != null && customAudioPath.isNotEmpty()) {
        Log.d(RENDER_TAG, "Adding custom audio track: $customAudioPath")
        Log.d(RENDER_TAG, "Custom audio volume: ${customAudioVolume ?: 1.0f}")
        
        val audioFile = File(customAudioPath)
        if (!audioFile.exists()) {
            Log.e(RENDER_TAG, "Custom audio file not found: $customAudioPath")
        } else {
            // Get custom audio duration
            var customAudioDurationUs = 0L
            try {
                val extractor = MediaExtractor()
                extractor.setDataSource(customAudioPath)
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        customAudioDurationUs = format.getLong(MediaFormat.KEY_DURATION)
                        Log.d(RENDER_TAG, "Custom audio duration: ${customAudioDurationUs / 1000} ms")
                        break
                    }
                }
                extractor.release()
            } catch (e: Exception) {
                Log.e(RENDER_TAG, "Failed to get custom audio duration: ${e.message}")
            }
            
            // Build audio effects for custom audio (will be reused for all repetitions)
            val customAudioProcessors = mutableListOf<AudioProcessor>()
            
            // Add channel mixing to normalize custom audio to stereo (like video audio)
            if (needsNormalization) {
                val channelMixer = ChannelMixingAudioProcessor()
                channelMixer.putChannelMixingMatrix(
                    ChannelMixingMatrix.create(2, 2) // Stereo to stereo
                )
                channelMixer.putChannelMixingMatrix(
                    ChannelMixingMatrix.create(1, 2) // Mono to stereo
                )
                customAudioProcessors.add(channelMixer)
            }
            
            // Add volume processor if needed
            if (customAudioVolume != null && customAudioVolume != 1.0f) {
                customAudioProcessors.add(VolumeAudioProcessor(customAudioVolume))
                Log.d(RENDER_TAG, "Added volume processor for custom audio: ${customAudioVolume}x")
            }
            
            val audioEffects = Effects(customAudioProcessors, emptyList())
            
            // Create multiple audio items if custom audio is shorter than video (looping)
            val audioItems = mutableListOf<EditedMediaItem>()
            
            if (customAudioDurationUs > 0 && totalVideoDurationUs > 0) {
                var remainingDurationUs = totalVideoDurationUs
                var loopCount = 0
                
                while (remainingDurationUs > 0) {
                    loopCount++
                    val audioMediaItemBuilder = MediaItem.Builder()
                        .setUri(Uri.fromFile(audioFile))
                    
                    // If this is the last loop and audio is longer than remaining duration, trim it
                    if (remainingDurationUs < customAudioDurationUs) {
                        val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(0)
                            .setEndPositionMs(remainingDurationUs / 1000)
                            .build()
                        audioMediaItemBuilder.setClippingConfiguration(clippingConfig)
                        Log.d(RENDER_TAG, "Loop $loopCount: Trimming audio to ${remainingDurationUs / 1000} ms (final loop)")
                    } else {
                        Log.d(RENDER_TAG, "Loop $loopCount: Using full audio duration ${customAudioDurationUs / 1000} ms")
                    }
                    
                    val audioMediaItem = audioMediaItemBuilder.build()
                    
                    val audioEditedItem = EditedMediaItem.Builder(audioMediaItem)
                        .setRemoveVideo(true) // Only keep audio from this track
                        .setEffects(audioEffects)
                        .build()
                    
                    audioItems.add(audioEditedItem)
                    remainingDurationUs -= customAudioDurationUs
                }
                
                Log.d(RENDER_TAG, "Custom audio will loop $loopCount times to match video duration")
            } else {
                // Fallback: just add audio once without looping
                val audioMediaItemBuilder = MediaItem.Builder()
                    .setUri(Uri.fromFile(audioFile))
                
                if (totalVideoDurationUs > 0) {
                    val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(0)
                        .setEndPositionMs(totalVideoDurationUs / 1000)
                        .build()
                    audioMediaItemBuilder.setClippingConfiguration(clippingConfig)
                    Log.d(RENDER_TAG, "Trimming custom audio to video duration: ${totalVideoDurationUs / 1000} ms (no loop)")
                }
                
                val audioMediaItem = audioMediaItemBuilder.build()
                val audioEditedItem = EditedMediaItem.Builder(audioMediaItem)
                    .setRemoveVideo(true)
                    .setEffects(audioEffects)
                    .build()
                
                audioItems.add(audioEditedItem)
            }
            
            // Create SEPARATE sequence for custom audio so it plays in parallel with video
            // Multiple items in same sequence will play sequentially, creating a loop effect
            val audioSequence = EditedMediaItemSequence(audioItems)
            sequences.add(audioSequence)
            Log.d(RENDER_TAG, "Custom audio sequence added with ${audioItems.size} item(s)")
        }
    }
    
    // Build composition with all sequences (video + optional audio in parallel)
    val composition = Composition.Builder(sequences).build()
    Log.d(RENDER_TAG, "Composition created successfully with ${sequences.size} sequences")
    
    return composition
}
