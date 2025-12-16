package ch.waio.pro_video_editor.src.features.render.helpers

import RENDER_TAG
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.media3.common.Effect
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import ch.waio.pro_video_editor.src.features.render.utils.getRotatedVideoDimensions
import java.io.File

/**
 * Applies static image overlay on video.
 *
 * Scales the image to match video dimensions after considering:
 * - Video rotation (dimension swap for 90°/270°)
 * - Applied cropping
 * - Applied scaling
 *
 * The overlay is rendered as a static bitmap on top of the video.
 *
 * @param videoEffects List to add overlay effect to
 * @param inputFile Video file for dimension detection
 * @param imageBytes PNG/JPEG image as byte array
 * @param rotationDegrees Applied rotation (affects dimensions)
 * @param cropWidth Applied crop width (affects overlay size)
 * @param cropHeight Applied crop height (affects overlay size)
 * @param scaleX Applied horizontal scale (affects overlay size)
 * @param scaleY Applied vertical scale (affects overlay size)
 */
@UnstableApi
fun applyImageLayer(
    videoEffects: MutableList<Effect>,
    inputFile: File,
    imageBytes: ByteArray?,
    rotationDegrees: Float,
    cropWidth: Int?,
    cropHeight: Int?,
    scaleX: Float?,
    scaleY: Float?,
) {
    if (imageBytes == null) return

    var (videoWidth, videoHeight, videoRotation) = getRotatedVideoDimensions(
        inputFile,
        rotationDegrees
    )

    var isRotated90Deg = videoRotation == 90 || videoRotation == 270;
    if (cropWidth != null) {
        if (isRotated90Deg) {
            videoHeight = cropWidth;
        } else {
            videoWidth = cropWidth;
        }
    }
    if (cropHeight != null) {
        if (isRotated90Deg) {
            videoWidth = cropHeight;
        } else {
            videoHeight = cropHeight;
        }
    }

    if (scaleX != null) videoWidth = (videoWidth * scaleX).toInt()
    if (scaleY != null) videoHeight = (videoHeight * scaleY).toInt()

    Log.d(
        RENDER_TAG,
        "Applying image overlay: ${imageBytes.size / 1024} KB, scaled to ${videoWidth}x$videoHeight"
    )

    val overlayBitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
    val scaledOverlay =
        Bitmap.createScaledBitmap(overlayBitmap, videoWidth, videoHeight, true)

    val bitmapOverlay = BitmapOverlay.createStaticBitmapOverlay(scaledOverlay)
    val overlayEffect = OverlayEffect(listOf(bitmapOverlay))

    videoEffects += overlayEffect
}

