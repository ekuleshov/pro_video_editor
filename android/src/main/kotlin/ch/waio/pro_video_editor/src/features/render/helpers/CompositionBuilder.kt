package ch.waio.pro_video_editor.src.features.render.helpers

import RENDER_TAG
import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import androidx.media3.common.Effect
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItemSequence
import ch.waio.pro_video_editor.src.features.render.models.RenderConfig
import ch.waio.pro_video_editor.src.features.render.models.VideoClip

/**
 * Main builder class for creating Media3 Compositions from render configurations.
 * 
 * Orchestrates video sequences, custom audio tracks, audio normalization,
 * and sample rate compatibility checking. This class delegates the actual
 * building to specialized builders (VideoSequenceBuilder, AudioSequenceBuilder).
 */
@UnstableApi
class CompositionBuilder(
    private val context: Context,
    private val config: RenderConfig,
    private val onAudioMixProgress: ((Double) -> Unit)? = null
) {
    
    private var videoEffects: List<Effect> = emptyList()
    private var audioEffects: List<AudioProcessor> = emptyList()

    /**
     * Sets the video effects to apply from EffectsProcessor.
     */
    fun setVideoEffects(effects: List<Effect>): CompositionBuilder {
        this.videoEffects = effects
        return this
    }

    /**
     * Sets the audio effects to apply from EffectsProcessor.
     */
    fun setAudioEffects(effects: List<AudioProcessor>): CompositionBuilder {
        this.audioEffects = effects
        return this
    }

    /**
     * Builds the complete composition with video and optional custom audio.
     * 
     * @return Composition ready for Media3 Transformer, or null if no video clips
     */
    fun build(): Composition? {
        if (config.videoClips.isEmpty()) {
            return null
        }

        Log.d(RENDER_TAG, "Creating composition with ${config.videoClips.size} video clips")
        Log.d(RENDER_TAG, "Audio enabled: ${config.enableAudio}")

        val rotationDegrees = (4 - (config.rotateTurns ?: 0)) * 90f

        // Build video sequence
        val videoBuilder = VideoSequenceBuilder(config.videoClips)
            .setVideoEffects(videoEffects)
            .setAudioEffects(audioEffects)
            .setRotation(rotationDegrees)
            .setFlip(config.flipX, config.flipY)
            .setCrop(config.cropWidth, config.cropHeight, config.cropX, config.cropY)
            .setImageLayer(config.imageBytes, config.scaleX, config.scaleY)
            .setEnableAudio(config.enableAudio)
            .setOriginalAudioVolume(config.originalAudioVolume)
            .setGlobalTrim(config.startUs, config.endUs)

        // Detect if audio normalization is needed
        val needsNormalization = videoBuilder.detectAudioNormalizationNeeded()
        videoBuilder.setAudioNormalization(needsNormalization)

        // Check if we need to mix custom audio with original
        val needsAudioMixing = config.customAudioPath != null && 
                               config.customAudioPath.isNotEmpty() &&
                               config.originalAudioVolume != null && 
                               config.originalAudioVolume > 0.0f

        // If mixing, we need to remove audio from video and provide mixed track separately
        val forceRemoveOriginalAudio = needsAudioMixing

        videoBuilder.setForceRemoveAudio(forceRemoveOriginalAudio)

        // Build video sequence (with or without audio based on mixing needs)
        val videoSequence = videoBuilder.build()
        
        // Prepare sequences list
        val sequences = mutableListOf<EditedMediaItemSequence>()
        sequences.add(videoSequence)
        Log.d(RENDER_TAG, "Created video EditedMediaItemSequence with ${config.videoClips.size} items")

        // Log audio mixing status
        if (needsAudioMixing) {
            Log.d(
                RENDER_TAG,
                "✅ Audio mixing ENABLED (original: ${config.originalAudioVolume}x, custom: ${config.customAudioVolume}x)"
            )
            Log.d(RENDER_TAG, "Both original and custom audio tracks will be mixed")
        }

        // Add custom audio sequence if provided - mix it with video audio
        if (config.customAudioPath != null && config.customAudioPath.isNotEmpty()) {
            val totalVideoDuration = videoBuilder.calculateTotalDuration()
            
            // Get first video path for audio extraction
            val videoInputPath = config.videoClips.firstOrNull()?.inputPath
            
            if (videoInputPath != null && needsAudioMixing) {
                // Mix both audios into a single track (preserves video's original audio quality)
                Log.d(RENDER_TAG, "🎵 Mixing video audio with custom audio (preserves original quality)")
                
                val audioMixer = AudioMixer(context)
                val mixedAudioPath = audioMixer.mixAudio(
                    videoPath = videoInputPath,
                    customAudioPath = config.customAudioPath,
                    videoVolume = config.originalAudioVolume ?: 1f,
                    customVolume = config.customAudioVolume ?: 1f,
                    targetDuration = totalVideoDuration,
                    onProgress = onAudioMixProgress
                )
                
                Log.d(RENDER_TAG, "Mixed audio created: $mixedAudioPath")
                
                // Add mixed audio sequence (video already has audio removed)
                val audioSequence = AudioSequenceBuilder(mixedAudioPath, totalVideoDuration)
                    .setVolume(1.0f) // Already mixed with correct volumes
                    .setNormalization(needsNormalization)
                    .build()

                if (audioSequence != null) {
                    sequences.add(audioSequence)
                    Log.d(RENDER_TAG, "Mixed audio sequence added")
                }
            } else if (!needsAudioMixing) {
                // Only custom audio, no mixing needed
                Log.d(RENDER_TAG, "Only custom audio (no video audio mixing)")
                val audioSequence = AudioSequenceBuilder(config.customAudioPath, totalVideoDuration)
                    .setVolume(config.customAudioVolume ?: 1.0f)
                    .setNormalization(needsNormalization)
                    .build()

                if (audioSequence != null) {
                    sequences.add(audioSequence)
                    Log.d(RENDER_TAG, "Custom audio sequence added")
                }
            }
        }

        // Build final composition
        val composition = Composition.Builder(sequences).build()
        Log.d(RENDER_TAG, "Composition created successfully with ${sequences.size} sequences")

        return composition
    }
}