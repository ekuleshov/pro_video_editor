package ch.waio.pro_video_editor.src.features.render.helpers

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.muxer.Mp4Muxer
import androidx.media3.muxer.Muxer
import androidx.media3.muxer.MuxerException
import androidx.media3.muxer.SeekableMuxerOutput
import com.google.common.collect.ImmutableList
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * A configurable Muxer.Factory that allows control over streaming optimization.
 *
 * This factory wraps Mp4Muxer and exposes the `attemptStreamableOutputEnabled` setting,
 * which controls whether the muxer attempts to write the moov atom at the beginning
 * of the file for progressive streaming (fast start).
 *
 * Note: On Android, this is "best effort" - setting to true does not guarantee
 * a streamable output, unlike iOS/macOS where AVFoundation guarantees it.
 *
 * @param attemptStreamableOutput Whether to attempt writing moov atom at the start.
 *        Default is true for progressive streaming compatibility.
 */
@UnstableApi
class ConfigurableMp4MuxerFactory(
    private val attemptStreamableOutput: Boolean = true
) : Muxer.Factory {

    override fun create(path: String): Muxer {
        val outputStream: FileOutputStream
        try {
            outputStream = FileOutputStream(path)
        } catch (e: FileNotFoundException) {
            throw MuxerException("Error creating file output stream", e)
        }

        val muxer = Mp4Muxer.Builder(SeekableMuxerOutput.of(outputStream))
            .setAttemptStreamableOutputEnabled(attemptStreamableOutput)
            .build()

        return ConfigurableMp4Muxer(muxer)
    }

    override fun getSupportedSampleMimeTypes(trackType: Int): ImmutableList<String> {
        return when (trackType) {
            C.TRACK_TYPE_VIDEO -> Mp4Muxer.SUPPORTED_VIDEO_SAMPLE_MIME_TYPES
            C.TRACK_TYPE_AUDIO -> Mp4Muxer.SUPPORTED_AUDIO_SAMPLE_MIME_TYPES
            else -> ImmutableList.of()
        }
    }
}

/**
 * Wrapper around Mp4Muxer to implement the Muxer interface for Transformer.
 */
@UnstableApi
private class ConfigurableMp4Muxer(
    private val muxer: Mp4Muxer
) : Muxer {

    override fun addTrack(format: Format): Int {
        return muxer.addTrack(format)
    }

    override fun writeSampleData(
        trackId: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: androidx.media3.muxer.BufferInfo
    ) {
        muxer.writeSampleData(trackId, byteBuffer, bufferInfo)
    }

    override fun addMetadataEntry(metadataEntry: androidx.media3.common.Metadata.Entry) {
        muxer.addMetadataEntry(metadataEntry)
    }

    override fun close() {
        muxer.close()
    }
}
