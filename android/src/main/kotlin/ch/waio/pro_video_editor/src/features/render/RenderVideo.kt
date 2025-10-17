package ch.waio.pro_video_editor.src.features.render

import PACKAGE_TAG
import RENDER_TAG
import android.content.Context
import android.media.MediaCodecInfo
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import applyBitrate
import applyBlur
import applyColorMatrix
import applyComposition
import applyCrop
import applyFlip
import applyImageLayer
import applyPlaybackSpeed
import applyRotation
import applyScale
import mapFormatToMimeType
import java.io.File

// VideoClip Data Class Import
import VideoClip

@UnstableApi
class RenderVideo(private val context: Context) {
    fun render(
        videoClips: List<VideoClip>,
        imageBytes: ByteArray?,
        inputFormat: String,
        outputFormat: String,
        outputPath: String?,
        rotateTurns: Int?,
        flipX: Boolean = false,
        flipY: Boolean = false,
        cropWidth: Int?,
        cropHeight: Int?,
        cropX: Int?,
        cropY: Int?,
        scaleX: Float?,
        scaleY: Float?,
        bitrate: Int?,
        enableAudio: Boolean = true,
        playbackSpeed: Float? = null,
        colorMatrixList: List<List<Double>>,
        blur: Double?,
        customAudioPath: String? = null,
        originalAudioVolume: Float? = null,
        customAudioVolume: Float? = null,
        onProgress: (Double) -> Unit,
        onComplete: (ByteArray?) -> Unit,
        onError: (Throwable) -> Unit
    ) {
        val outputFile =
            if (outputPath != null) {
                File(outputPath)
            } else {
                File(
                    context.cacheDir,
                    "video_output_${System.currentTimeMillis()}.$outputFormat"
                )
            }

        val videoEffects = mutableListOf<Effect>()
        val audioEffects = mutableListOf<AudioProcessor>()

        val rotationDegrees = (4 - (rotateTurns ?: 0)) * 90f

        applyRotation(videoEffects, rotationDegrees)
        applyFlip(videoEffects, flipX, flipY)
        applyScale(videoEffects, scaleX, scaleY)
        applyColorMatrix(videoEffects, colorMatrixList)
        applyBlur(videoEffects, blur)
        applyPlaybackSpeed(videoEffects, audioEffects, playbackSpeed)

        var shouldStopPolling = false
        val outputMimeType = mapFormatToMimeType(outputFormat)
        val encoderFactoryBuilder = DefaultEncoderFactory.Builder(context)

        applyBitrate(encoderFactoryBuilder, outputMimeType, bitrate)

        val mainHandler = Handler(Looper.getMainLooper())

        // Declare it before so it's visible in the listener
        lateinit var transformer: Transformer

        transformer = Transformer.Builder(context)
            .setEncoderFactory(encoderFactoryBuilder.build())
            .setVideoMimeType(outputMimeType)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, result: ExportResult) {
                    shouldStopPolling = true;
                    try {
                        if (outputPath != null) {
                            onComplete(null)
                        } else {
                            val resultBytes = outputFile.readBytes()
                            onComplete(resultBytes)
                        }
                    } catch (e: Exception) {
                        onError(e)
                    } finally {
                        mainHandler.removeCallbacksAndMessages(null) // stop progress polling
                        if (outputPath == null) outputFile.delete()
                    }
                }

                override fun onError(
                    composition: Composition,
                    result: ExportResult,
                    exception: ExportException
                ) {
                    shouldStopPolling = true;
                    onError(exception)
                    if (outputPath == null) outputFile.delete()
                }
            })
            .build()

        // Start transformation
        val composition = applyComposition(
            videoClips = videoClips,
            videoEffects = videoEffects,
            audioEffects = audioEffects,
            enableAudio = enableAudio,
            imageBytes = imageBytes,
            rotationDegrees = rotationDegrees,
            flipX = flipX,
            flipY = flipY,
            cropWidth = cropWidth,
            cropHeight = cropHeight,
            cropX = cropX,
            cropY = cropY,
            scaleX = scaleX,
            scaleY = scaleY,
            customAudioPath = customAudioPath,
            originalAudioVolume = originalAudioVolume,
            customAudioVolume = customAudioVolume
        )
        if (composition != null) {
            transformer.start(composition, outputFile.absolutePath)
        } else {
            onError(IllegalStateException("Failed to create composition"))
            return
        }

        // Progress tracking setup
        val progressHolder = ProgressHolder()

        mainHandler.post(object : Runnable {
            override fun run() {
                if (shouldStopPolling) return

                val progressState = transformer.getProgress(progressHolder)
                if (progressHolder.progress >= 0) {
                    onProgress(progressHolder.progress / 100.0)
                }

                // Continue polling if transformer started
                if (!shouldStopPolling && progressState != Transformer.PROGRESS_STATE_NOT_STARTED) {
                    mainHandler.postDelayed(this, 200)
                }
            }
        })
    }
}