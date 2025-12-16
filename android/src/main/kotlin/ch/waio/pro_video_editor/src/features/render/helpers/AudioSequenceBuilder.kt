package ch.waio.pro_video_editor.src.features.render.helpers

import RENDER_TAG
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.File

/**
 * Builder class for creating custom audio sequences in video compositions.
 *
 * Handles looping, volume control, and channel normalization for custom
 * audio tracks that play alongside or replace original video audio.
 */
@UnstableApi
class AudioSequenceBuilder(
    private val audioPath: String,
    private val videoDurationUs: Long
) {
    private var volume: Float = 1.0f
    private var needsNormalization: Boolean = false

    /**
     * Sets the volume multiplier for the custom audio.
     *
     * @param volume Volume factor (0.0=silent, 1.0=unchanged, >1.0=amplified)
     */
    fun setVolume(volume: Float): AudioSequenceBuilder {
        this.volume = volume
        return this
    }

    /**
     * Enables channel normalization (convert to stereo).
     *
     * Should be enabled when video clips have different channel counts
     * to ensure compatibility.
     */
    fun setNormalization(enabled: Boolean): AudioSequenceBuilder {
        this.needsNormalization = enabled
        return this
    }

    /**
     * Builds the audio sequence with looping to match video duration.
     *
     * @return EditedMediaItemSequence for custom audio, or null if file not found
     */
    fun build(): EditedMediaItemSequence? {
        Log.d(RENDER_TAG, "Building custom audio sequence: $audioPath")
        Log.d(RENDER_TAG, "Custom audio volume: $volume")

        val audioFile = File(audioPath)
        if (!audioFile.exists()) {
            Log.e(RENDER_TAG, "Custom audio file not found: $audioPath")
            return null
        }

        val audioDurationUs = MediaInfoExtractor.getAudioDuration(audioPath)
        if (audioDurationUs == 0L) {
            Log.w(RENDER_TAG, "Cannot determine custom audio duration")
            return null
        }

        // Build audio effects
        val audioProcessors = buildAudioProcessors()
        val audioEffects = Effects(audioProcessors, emptyList())

        // Create audio items with looping
        val audioItems = createLoopedAudioItems(audioFile, audioDurationUs, audioEffects)

        return EditedMediaItemSequence(audioItems)
    }

    /**
     * Checks if custom audio sample rate matches video audio.
     *
     * @param expectedSampleRate Expected sample rate (typically 48000 Hz for video)
     * @return true if sample rates match or detection failed (assume safe)
     */
    fun checkSampleRateCompatibility(expectedSampleRate: Int = 48000): Boolean {
        val customSampleRate = MediaInfoExtractor.getAudioSampleRate(audioPath)

        if (customSampleRate == 0) {
            return true // Cannot detect, assume safe
        }

        val compatible = customSampleRate == expectedSampleRate

        if (!compatible) {
            Log.e(RENDER_TAG, "ERROR: Cannot mix audio with different sample rates!")
            Log.e(RENDER_TAG, "Expected: ${expectedSampleRate}Hz, Custom: ${customSampleRate}Hz")
            Log.e(RENDER_TAG, "WORKAROUND: Original audio must be removed (replace mode)")
        } else {
            Log.d(RENDER_TAG, "Audio mixing is safe - sample rates match ($expectedSampleRate Hz)")
        }

        return compatible
    }

    /**
     * Builds audio processors for custom audio (channel mixing + volume).
     */
    private fun buildAudioProcessors(): List<AudioProcessor> {
        val processors = mutableListOf<AudioProcessor>()

        // Add channel mixing if needed
        if (needsNormalization) {
            val channelMixer = ChannelMixingAudioProcessor()
            channelMixer.putChannelMixingMatrix(
                ChannelMixingMatrix.create(2, 2) // Stereo to stereo
            )
            channelMixer.putChannelMixingMatrix(
                ChannelMixingMatrix.create(1, 2) // Mono to stereo
            )
            processors.add(channelMixer)
            Log.d(RENDER_TAG, "Added channel normalization for custom audio")
        }

        // Add volume processor if needed
        if (volume != 1.0f) {
            processors.add(VolumeAudioProcessor(volume))
            Log.d(RENDER_TAG, "Added volume processor for custom audio: ${volume}x")
        }

        return processors
    }

    /**
     * Creates audio items with looping to match video duration.
     */
    private fun createLoopedAudioItems(
        audioFile: File,
        audioDurationUs: Long,
        effects: Effects
    ): List<EditedMediaItem> {
        val audioItems = mutableListOf<EditedMediaItem>()

        if (audioDurationUs <= 0 || videoDurationUs <= 0) {
            // Fallback: add audio once without duration constraints
            val audioItem = createAudioItem(audioFile, null, effects)
            audioItems.add(audioItem)
            return audioItems
        }

        var remainingDurationUs = videoDurationUs
        var loopCount = 0

        while (remainingDurationUs > 0) {
            loopCount++
            val trimDurationUs = if (remainingDurationUs < audioDurationUs) {
                Log.d(
                    RENDER_TAG,
                    "Loop $loopCount: Trimming audio to ${remainingDurationUs / 1000} ms (final loop)"
                )
                remainingDurationUs
            } else {
                Log.d(
                    RENDER_TAG,
                    "Loop $loopCount: Using full audio duration ${audioDurationUs / 1000} ms"
                )
                null
            }

            val audioItem = createAudioItem(audioFile, trimDurationUs, effects)
            audioItems.add(audioItem)
            remainingDurationUs -= audioDurationUs
        }

        Log.d(RENDER_TAG, "Custom audio will loop $loopCount times to match video duration")
        return audioItems
    }

    /**
     * Creates a single audio EditedMediaItem with optional trimming.
     */
    private fun createAudioItem(
        audioFile: File,
        trimDurationUs: Long?,
        effects: Effects
    ): EditedMediaItem {
        val mediaItemBuilder = MediaItem.Builder().setUri(Uri.fromFile(audioFile))

        if (trimDurationUs != null) {
            val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(0)
                .setEndPositionMs(trimDurationUs / 1000)
                .build()
            mediaItemBuilder.setClippingConfiguration(clippingConfig)
        }

        val mediaItem = mediaItemBuilder.build()
        return EditedMediaItem.Builder(mediaItem)
            .setRemoveVideo(true)
            .setEffects(effects)
            .build()
    }
}
