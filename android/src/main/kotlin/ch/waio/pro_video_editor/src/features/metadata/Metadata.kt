package ch.waio.pro_video_editor.src.features.metadata

import android.content.Context
import android.media.MediaMetadataRetriever
import ch.waio.pro_video_editor.src.features.metadata.models.MetadataConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File

/**
 * Service for extracting metadata from video files.
 *
 * This class provides functionality to retrieve comprehensive metadata information
 * from video files, including technical properties (dimensions, duration, bitrate)
 * and descriptive metadata (title, artist, album).
 */
class Metadata(private val context: Context) {

    // Create a dedicated coroutine scope for this service
    // SupervisorJob ensures that failures don't cancel sibling coroutines
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /**
     * Asynchronously retrieves metadata from a video file.
     *
     * This method runs on a background thread and extracts all available metadata
     * from the video file specified in the configuration. The operation is non-blocking
     * and results are delivered via callbacks.
     *
     * @param config Configuration containing the video file path and extraction parameters
     * @param onComplete Callback invoked with extracted metadata map on success
     * @param onError Callback invoked with exception if extraction fails
     */
    fun getMetadata(
        config: MetadataConfig,
        onComplete: (Map<String, Any>) -> Unit,
        onError: (Exception) -> Unit
    ) {
        scope.launch {
            try {
                val result = processVideo(config)
                onComplete(result)
            } catch (e: Exception) {
                onError(e)
            }
        }
    }

    /**
     * Internal method that performs the actual metadata extraction.
     *
     * Uses Android's MediaMetadataRetriever to extract both numeric and text-based
     * metadata from the video file. The extraction process is organized into categories:
     * - File properties (file size)
     * - Numeric metadata (duration, dimensions, rotation, bitrate)
     * - Text metadata (title, artist, author, album information)
     *
     * @param config Configuration containing the video file path
     * @return Map containing all extracted metadata with string keys and typed values
     * @throws Exception if the file cannot be accessed or metadata extraction fails
     */
    private fun processVideo(config: MetadataConfig): Map<String, Any> {
        val tempFile = File(config.inputPath)
        val retriever = MediaMetadataRetriever()

        try {
            retriever.setDataSource(tempFile.absolutePath)

            // Initialize metadata map with file size
            val metadata = mutableMapOf<String, Any>(
                "fileSize" to tempFile.length()
            )

            // Define numeric metadata keys mapping
            // These values require numeric parsing (Int or Double)
            val numericMetadata = mapOf(
                "duration" to MediaMetadataRetriever.METADATA_KEY_DURATION,
                "width" to MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
                "height" to MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
                "rotation" to MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
                "bitrate" to MediaMetadataRetriever.METADATA_KEY_BITRATE
            )

            // Extract and parse numeric metadata
            // Duration is returned as Double (milliseconds), all others as Int
            numericMetadata.forEach { (key, metadataKey) ->
                val value = retriever.extractMetadata(metadataKey)
                metadata[key] = when (key) {
                    "duration" -> value?.toDoubleOrNull() ?: 0.0
                    else -> value?.toIntOrNull() ?: 0
                }
            }

            // Define text metadata keys mapping
            // These values are returned as-is (String)
            val textMetadata = mapOf(
                "title" to MediaMetadataRetriever.METADATA_KEY_TITLE,
                "artist" to MediaMetadataRetriever.METADATA_KEY_ARTIST,
                "author" to MediaMetadataRetriever.METADATA_KEY_AUTHOR,
                "album" to MediaMetadataRetriever.METADATA_KEY_ALBUM,
                "albumArtist" to MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST,
                "date" to MediaMetadataRetriever.METADATA_KEY_DATE
            )

            // Extract text metadata, default to empty string if not present
            textMetadata.forEach { (key, metadataKey) ->
                metadata[key] = retriever.extractMetadata(metadataKey) ?: ""
            }

            return metadata
        } finally {
            // Always release the retriever to free native resources
            retriever.release()
        }
    }

}
