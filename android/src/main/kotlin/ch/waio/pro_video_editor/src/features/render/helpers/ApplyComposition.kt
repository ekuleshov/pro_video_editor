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

data class VideoClip(
    val inputPath: String,
    val startUs: Long?,
    val endUs: Long?
)

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
    scaleY: Float?
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
        val effects = Effects(normalizedAudioEffects, clipVideoEffects)
        
        val editedMediaItemBuilder = EditedMediaItem.Builder(mediaItem).setEffects(effects)

        if (!enableAudio) {
            Log.d(RENDER_TAG, "Removing audio from clip $index (enableAudio=false)")
            editedMediaItemBuilder.setRemoveAudio(true)
        } else {
            Log.d(RENDER_TAG, "Keeping audio for clip $index")
        }

        val builtItem = editedMediaItemBuilder.build()
        Log.d(RENDER_TAG, "Built EditedMediaItem $index with ${clipVideoEffects.size} video effects")
        builtItem
    }

    Log.d(RENDER_TAG, "Total EditedMediaItems created: ${editedMediaItems.size}")
    
    // For video concatenation, all clips must be in ONE sequence to play sequentially
    // Multiple sequences would play in parallel (not what we want)
    val sequence = EditedMediaItemSequence(editedMediaItems)
    Log.d(RENDER_TAG, "Created EditedMediaItemSequence with ${editedMediaItems.size} items")

    val composition = Composition.Builder(listOf(sequence)).build()
    Log.d(RENDER_TAG, "Composition created successfully")
    
    return composition
}
