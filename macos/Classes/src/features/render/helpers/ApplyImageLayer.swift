import AVFoundation
import AppKit
import CoreImage

/// Applies an overlay image on top of video frames.
///
/// The image is composited over each video frame during rendering. The image
/// should be provided as encoded data (PNG, JPEG, etc.) and will be decoded
/// by the video compositor.
///
/// - Parameters:
///   - config: Video compositor configuration to modify.
///   - imageData: Encoded image data. If nil, no overlay is applied.
///
/// - Note: The image is positioned and scaled by the video compositor according
///         to its own logic (typically centered or full-frame).
func applyImageLayer(
    config: inout VideoCompositorConfig,
    imageData: Data?
) {
    config.overlayImage = imageData
    guard let data = imageData else { return }

    let sizeKB = Double(data.count) / 1024.0
    print("[\(Tags.render)] 🖼️ Applying overlay image (\(String(format: "%.1f", sizeKB)) KB)")
}
