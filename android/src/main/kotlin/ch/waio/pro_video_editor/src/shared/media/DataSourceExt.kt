package ch.waio.pro_video_editor.src.shared.media

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import java.io.File
import java.io.IOException

/**
 * Converts a path string (either a `content://` URI or a filesystem path) into an Android [Uri].
 * Content URIs are parsed directly, while filesystem paths are converted via [Uri.fromFile].
 */
fun String.toContentOrFileUri(): Uri =
    if (startsWith("content://")) toUri() else Uri.fromFile(File(this))

/**
 * Sets the URI on a [MediaItem.Builder] from a path string that can be either a `content://` URI
 * or a filesystem path.
 */
fun MediaItem.Builder.contentUri(path: String): MediaItem.Builder =
    setUri(path.toContentOrFileUri())

/**
 * Sets the data source on a [MediaExtractor] for either a content URI or a file path.
 */
@Throws(IOException::class)
fun MediaExtractor.contentDataSource(context: Context, path: String) {
    if (path.startsWith("content://")) {
        setDataSource(context, path.toUri(), null)
    } else {
        setDataSource(path)
    }
}

/**
 * Sets the data source on a [MediaMetadataRetriever] for either a content URI or a file path.
 */
@Throws(IllegalArgumentException::class, SecurityException::class)
fun MediaMetadataRetriever.contentDataSource(context: Context, path: String) {
    if (path.startsWith("content://")) {
        setDataSource(context, path.toUri())
    } else {
        setDataSource(path)
    }
}
