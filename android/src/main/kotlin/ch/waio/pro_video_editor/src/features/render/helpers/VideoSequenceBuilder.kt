package ch.waio.pro_video_editor.src.features.render.helpers

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
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.File

/**
 * Represents a video clip segment with optional trimming.
 *
 * @property inputPath Absolute path to video file
 * @property startUs Start time in microseconds (null = from beginning)
 * @property endUs End time in microseconds (null = until end)
 */
data class VideoClip(
    val inputPath: String,
    val startUs: Long?,
    val endUs: Long?
)

/**
 * Builder class for creating video sequences with effects in video compositions.
 *
 * Handles multiple video clips, effects, audio normalization, volume control,
 * cropping, and image overlays.
 */
@UnstableApi
class VideoSequenceBuilder(
    private val videoClips: List<VideoClip>
) {
    private var videoEffects: List<Effect> = emptyList()
    private var audioEffects: List<AudioProcessor> = emptyList()
    private var rotationDegrees: Float = 0f
    private var flipX: Boolean = false
    private var flipY: Boolean = false
    private var cropConfig: CropConfig? = null
    private var imageLayerConfig: ImageLayerConfig? = null
    private var enableAudio: Boolean = true
    private var originalAudioVolume: Float? = null
    private var needsAudioNormalization: Boolean = false
    private var forceRemoveAudio: Boolean = false

    data class CropConfig(
        val width: Int?,
        val height: Int?,
        val x: Int?,
        val y: Int?
    )

    data class ImageLayerConfig(
        val imageBytes: ByteArray?,
        val scaleX: Float?,
        val scaleY: Float?
    )

    /**
     * Sets the video effects to apply to all clips.
     */
    fun setVideoEffects(effects: List<Effect>): VideoSequenceBuilder {
        this.videoEffects = effects
        return this
    }

    /**
     * Sets the audio effects to apply to all clips.
     */
    fun setAudioEffects(effects: List<AudioProcessor>): VideoSequenceBuilder {
        this.audioEffects = effects
        return this
    }

    /**
     * Sets rotation in degrees (0, 90, 180, 270).
     */
    fun setRotation(degrees: Float): VideoSequenceBuilder {
        this.rotationDegrees = degrees
        return this
    }

    /**
     * Sets flip configuration.
     */
    fun setFlip(flipX: Boolean, flipY: Boolean): VideoSequenceBuilder {
        this.flipX = flipX
        this.flipY = flipY
        return this
    }

    /**
     * Sets crop configuration.
     */
    fun setCrop(width: Int?, height: Int?, x: Int?, y: Int?): VideoSequenceBuilder {
        this.cropConfig = CropConfig(width, height, x, y)
        return this
    }

    /**
     * Sets image layer overlay configuration.
     */
    fun setImageLayer(
        imageBytes: ByteArray?,
        scaleX: Float?,
        scaleY: Float?
    ): VideoSequenceBuilder {
        this.imageLayerConfig = ImageLayerConfig(imageBytes, scaleX, scaleY)
        return this
    }

    /**
     * Enables or disables audio in the output.
     */
    fun setEnableAudio(enabled: Boolean): VideoSequenceBuilder {
        this.enableAudio = enabled
        return this
    }

    /**
     * Sets the volume for original video audio.
     */
    fun setOriginalAudioVolume(volume: Float?): VideoSequenceBuilder {
        this.originalAudioVolume = volume
        return this
    }

    /**
     * Enables audio channel normalization (convert all to stereo).
     *
     * Should be enabled when clips have different channel counts.
     */
    fun setAudioNormalization(enabled: Boolean): VideoSequenceBuilder {
        this.needsAudioNormalization = enabled
        return this
    }

    /**
     * Forces removal of audio from all clips.
     *
     * Used when custom audio sample rate is incompatible with video audio.
     */
    fun setForceRemoveAudio(enabled: Boolean): VideoSequenceBuilder {
        this.forceRemoveAudio = enabled
        return this
    }

    /**
     * Detects if audio normalization is needed across video clips.
     *
     * @return true if clips have different audio channel counts
     */
    fun detectAudioNormalizationNeeded(): Boolean {
        if (!enableAudio || videoClips.size <= 1) {
            return false
        }

        val audioChannelCounts = videoClips.mapNotNull { clip ->
            MediaInfoExtractor.getAudioChannelCount(clip.inputPath)
        }

        val needsNormalization = audioChannelCounts.isNotEmpty() &&
                audioChannelCounts.toSet().size > 1

        if (needsNormalization) {
            Log.d(
                RENDER_TAG,
                "Audio normalization needed - detected different channel counts: $audioChannelCounts"
            )
        } else if (audioChannelCounts.isNotEmpty()) {
            Log.d(
                RENDER_TAG,
                "Audio normalization NOT needed - all videos have same channel count: ${audioChannelCounts.firstOrNull()}"
            )
        }

        return needsNormalization
    }

    /**
     * Calculates total duration of all video clips combined.
     *
     * @return Total duration in microseconds
     */
    fun calculateTotalDuration(): Long {
        var totalDurationUs = 0L
        videoClips.forEach { clip ->
            val clipDurationUs = when {
                clip.endUs != null && clip.startUs != null -> clip.endUs - clip.startUs
                clip.endUs != null -> clip.endUs
                else -> MediaInfoExtractor.getVideoDuration(clip.inputPath)
            }
            totalDurationUs += clipDurationUs
        }
        Log.d(RENDER_TAG, "Total video duration: ${totalDurationUs / 1000} ms")
        return totalDurationUs
    }

    /**
     * Builds the video sequence with all configured effects and settings.
     *
     * @return EditedMediaItemSequence for video clips
     */
    fun build(): EditedMediaItemSequence {
        Log.d(RENDER_TAG, "Building video sequence with ${videoClips.size} clips")
        Log.d(RENDER_TAG, "Audio enabled: $enableAudio")

        // Prepare normalized audio effects with channel mixing if needed
        val normalizedAudioEffects = if (needsAudioNormalization) {
            Log.d(RENDER_TAG, "Adding ChannelMixingAudioProcessor to normalize audio to stereo")
            buildChannelNormalizationEffects()
        } else {
            audioEffects.toList()
        }

        // Build EditedMediaItems for each clip
        val editedMediaItems = videoClips.mapIndexed { index, clip ->
            buildEditedMediaItem(index, clip, normalizedAudioEffects)
        }

        Log.d(RENDER_TAG, "Total EditedMediaItems created: ${editedMediaItems.size}")

        // Handle forced audio removal (sample rate mismatch)
        val finalVideoItems = if (forceRemoveAudio) {
            Log.w(
                RENDER_TAG,
                "Force removing original audio from all clips due to sample rate mismatch"
            )
            editedMediaItems.map { item ->
                EditedMediaItem.Builder(item.mediaItem)
                    .setEffects(item.effects)
                    .setRemoveAudio(true)
                    .build()
            }
        } else {
            editedMediaItems
        }

        // Check if first clip has no audio but later clips do
        val firstClipHasAudio = if (enableAudio && videoClips.isNotEmpty()) {
            MediaInfoExtractor.getAudioChannelCount(videoClips[0].inputPath)?.let { it > 0 } ?: false
        } else {
            true // If audio disabled, doesn't matter
        }

        val laterClipHasAudio = if (enableAudio && videoClips.size > 1) {
            videoClips.drop(1).any { clip ->
                MediaInfoExtractor.getAudioChannelCount(clip.inputPath)?.let { it > 0 } ?: false
            }
        } else {
            falseS
        }

        val needsForceAudioTrack = !firstClipHasAudio && laterClipHasAudio

        if (needsForceAudioTrack) {
            Log.w(
                RENDER_TAG,
                "First clip has no audio but later clips do - using experimentalSetForceAudioTrack"
            )
        }

        return EditedMediaItemSequence.Builder(finalVideoItems)
            .setIsLooping(false)
            .experimentalSetForceAudioTrack(needsForceAudioTrack)
            .build()
    }

    /**
     * Builds channel normalization effects (channel mixer + audio processors).
     */
    private fun buildChannelNormalizationEffects(): List<AudioProcessor> {
        val channelMixer = ChannelMixingAudioProcessor()

        // 5.1 Surround (6 channels) to Stereo (2 channels)
        val sixToTwo = floatArrayOf(
            1.0f, 0.0f, 0.7f, 0.0f, 0.7f, 0.0f,  // Left output
            0.0f, 1.0f, 0.7f, 0.0f, 0.0f, 0.7f   // Right output
        )
        channelMixer.putChannelMixingMatrix(
            ChannelMixingMatrix(6, 2, sixToTwo)
        )

        // Stereo (2 channels) to Stereo (2 channels) - passthrough
        channelMixer.putChannelMixingMatrix(
            ChannelMixingMatrix.create(2, 2)
        )

        // Mono (1 channel) to Stereo (2 channels)
        channelMixer.putChannelMixingMatrix(
            ChannelMixingMatrix.create(1, 2)
        )

        return mutableListOf<AudioProcessor>(channelMixer).apply { addAll(audioEffects) }
    }

    /**
     * Builds an EditedMediaItem for a single video clip with all effects.
     */
    private fun buildEditedMediaItem(
        index: Int,
        clip: VideoClip,
        normalizedAudioEffects: List<AudioProcessor>
    ): EditedMediaItem {
        Log.d(RENDER_TAG, "Processing clip $index: ${clip.inputPath}")
        val inputFile = File(clip.inputPath)

        if (!inputFile.exists()) {
            Log.e(RENDER_TAG, "ERROR: Video file does not exist: ${clip.inputPath}")
        } else {
            Log.d(RENDER_TAG, "Video file exists, size: ${inputFile.length()} bytes")
        }

        // Build MediaItem with optional trimming
        val mediaItemBuilder = MediaItem.Builder().setUri(Uri.fromFile(inputFile))

        if (clip.startUs != null || clip.endUs != null) {
            val startMs = (clip.startUs ?: 0L) / 1000
            val endMs = clip.endUs?.div(1000) ?: C.TIME_END_OF_SOURCE

            Log.d(
                RENDER_TAG,
                "Applying trim to clip ${clip.inputPath}: start=$startMs ms, end=$endMs ms"
            )

            val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(startMs)
                .setEndPositionMs(endMs)
                .build()

            mediaItemBuilder.setClippingConfiguration(clippingConfig)
        }

        val mediaItem = mediaItemBuilder.build()

        // Build video effects
        val clipVideoEffects = mutableListOf<Effect>()
        clipVideoEffects.addAll(videoEffects)

        // Apply crop if configured
        cropConfig?.let { crop ->
            applyCrop(
                clipVideoEffects,
                inputFile,
                rotationDegrees,
                flipX,
                flipY,
                crop.width,
                crop.height,
                crop.x,
                crop.y
            )
        }

        // Apply image layer if configured
        imageLayerConfig?.let { imageLayer ->
            applyImageLayer(
                clipVideoEffects,
                inputFile,
                imageLayer.imageBytes,
                rotationDegrees,
                cropConfig?.width,
                cropConfig?.height,
                imageLayer.scaleX,
                imageLayer.scaleY
            )
        }

        // Build audio effects with volume if needed
        val clipAudioEffects = if (originalAudioVolume != null && originalAudioVolume != 1.0f) {
            Log.d(
                RENDER_TAG,
                "Applying volume adjustment for clip $index: ${originalAudioVolume}x"
            )
            val volumeProcessor = VolumeAudioProcessor(originalAudioVolume!!)
            mutableListOf<AudioProcessor>(volumeProcessor).apply { addAll(normalizedAudioEffects) }
        } else {
            Log.d(
                RENDER_TAG,
                "No volume adjustment for clip $index (volume: ${originalAudioVolume ?: 1.0f})"
            )
            normalizedAudioEffects
        }

        val effects = Effects(clipAudioEffects, clipVideoEffects)

        // Determine if audio should be removed
        val shouldRemoveAudio = !enableAudio ||
                (originalAudioVolume != null && originalAudioVolume == 0.0f)

        if (shouldRemoveAudio) {
            Log.d(
                RENDER_TAG,
                "Removing audio from clip $index (enableAudio=$enableAudio, originalVolume=${originalAudioVolume ?: 1.0f})"
            )
        } else {
            Log.d(RENDER_TAG, "Keeping audio for clip $index (for mixing or normal playback)")
        }

        return EditedMediaItem.Builder(mediaItem)
            .setEffects(effects)
            .setRemoveAudio(shouldRemoveAudio)
            .build()
    }
}
