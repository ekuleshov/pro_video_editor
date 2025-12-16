package ch.waio.pro_video_editor.src.features.render.helpers

import RENDER_TAG
import android.util.Log
import androidx.media3.common.Effect
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItemSequence
import ch.waio.pro_video_editor.src.features.render.models.RenderConfig

/**
 * Main builder class for creating Media3 Compositions from render configurations.
 * 
 * Orchestrates video sequences, custom audio tracks, audio normalization,
 * and sample rate compatibility checking. This class delegates the actual
 * building to specialized builders (VideoSequenceBuilder, AudioSequenceBuilder).
 */
@UnstableApi
class CompositionBuilder(private val config: RenderConfig) {
    
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

        // Detect if audio normalization is needed
        val needsNormalization = videoBuilder.detectAudioNormalizationNeeded()
        videoBuilder.setAudioNormalization(needsNormalization)

        // Check if we need to mix custom audio with original
        val needsAudioMixing = config.customAudioPath != null && 
                               config.customAudioPath.isNotEmpty() &&
                               config.originalAudioVolume != null && 
                               config.originalAudioVolume > 0.0f

        // Check sample rate compatibility
        val forceRemoveOriginalAudio = if (needsAudioMixing) {
            val audioBuilder = AudioSequenceBuilder(
                config.customAudioPath!!,
                videoBuilder.calculateTotalDuration()
            )
            !audioBuilder.checkSampleRateCompatibility()
        } else {
            false
        }

        videoBuilder.setForceRemoveAudio(forceRemoveOriginalAudio)

        // Build video sequence
        val videoSequence = videoBuilder.build()
        
        // Prepare sequences list
        val sequences = mutableListOf<EditedMediaItemSequence>()
        sequences.add(videoSequence)
        Log.d(RENDER_TAG, "Created video EditedMediaItemSequence with ${config.videoClips.size} items")

        // Log audio mixing status
        if (needsAudioMixing && !forceRemoveOriginalAudio) {
            Log.w(
                RENDER_TAG,
                "✅ Audio mixing ENABLED (original: ${config.originalAudioVolume}x, custom: ${config.customAudioVolume}x)"
            )
            Log.w(RENDER_TAG, "✅ Sample rates are compatible - both audio tracks will be mixed")
        } else if (forceRemoveOriginalAudio) {
            Log.e(RENDER_TAG, "❌ Audio mixing DISABLED - sample rate mismatch detected")
            Log.e(RENDER_TAG, "❌ Only custom audio will be used (original audio removed)")
        }

        // Add custom audio sequence if provided
        if (config.customAudioPath != null && config.customAudioPath.isNotEmpty()) {
            val totalVideoDuration = videoBuilder.calculateTotalDuration()
            val audioSequence = AudioSequenceBuilder(config.customAudioPath, totalVideoDuration)
                .setVolume(config.customAudioVolume ?: 1.0f)
                .setNormalization(needsNormalization)
                .build()

            if (audioSequence != null) {
                sequences.add(audioSequence)
                Log.d(RENDER_TAG, "Custom audio sequence added")
            }
        }

        // Build final composition
        val composition = Composition.Builder(sequences).build()
        Log.d(RENDER_TAG, "Composition created successfully with ${sequences.size} sequences")

        return composition
    }
}
