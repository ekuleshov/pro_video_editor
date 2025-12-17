import Foundation

/// Represents a video clip segment with optional trimming.
///
/// This struct defines a portion of a video file that should be included in the render,
/// with optional start and end timestamps for precise trimming.
struct VideoClip {
    /// Absolute path to the video file
    let inputPath: String
    
    /// Start time in microseconds (nil = from beginning)
    let startUs: Int64?
    
    /// End time in microseconds (nil = until end)
    let endUs: Int64?
}

/// Configuration model for video rendering operations.
///
/// This struct encapsulates all parameters required for rendering a video with
/// effects, transformations, and audio mixing. It supports both single-video
/// and multi-video rendering with comprehensive effect options.
struct RenderConfig {
    /// List of video clips to render (concatenated in order)
    let videoClips: [VideoClip]
    
    /// Optional image data for image-to-video conversion
    let imageData: Data?
    
    /// Input format of the source video (e.g., "mp4", "mov")
    let inputFormat: String
    
    /// Output format for the rendered video (e.g., "mp4", "mov")
    let outputFormat: String
    
    /// Optional absolute path where output should be saved (nil = return bytes)
    let outputPath: String?
    
    /// Number of 90-degree clockwise rotations to apply (0-3)
    let rotateTurns: Int?
    
    /// Whether to flip video horizontally
    let flipX: Bool
    
    /// Whether to flip video vertically
    let flipY: Bool
    
    /// Crop width in pixels (nil = no crop)
    let cropWidth: Int?
    
    /// Crop height in pixels (nil = no crop)
    let cropHeight: Int?
    
    /// Crop X offset in pixels (nil = centered)
    let cropX: Int?
    
    /// Crop Y offset in pixels (nil = centered)
    let cropY: Int?
    
    /// Horizontal scale factor (nil = no scaling)
    let scaleX: Float?
    
    /// Vertical scale factor (nil = no scaling)
    let scaleY: Float?
    
    /// Target bitrate in bits per second (nil = auto)
    let bitrate: Int?
    
    /// Whether to include audio in output
    let enableAudio: Bool
    
    /// Playback speed multiplier (e.g., 2.0 = 2x speed)
    let playbackSpeed: Float?
    
    /// List of 4x4 color transformation matrices
    let colorMatrixList: [[Double]]
    
    /// Blur radius (nil = no blur, experimental feature)
    let blur: Double?
    
    /// Absolute path to custom audio file to mix in (nil = no custom audio)
    let customAudioPath: String?
    
    /// Volume for original video audio (0.0-1.0, nil = 1.0)
    let originalAudioVolume: Float?
    
    /// Volume for custom audio track (0.0-1.0, nil = 1.0)
    let customAudioVolume: Float?
    
    /// Creates a RenderConfig from Flutter method call arguments.
    ///
    /// - Parameter arguments: Dictionary containing the method call arguments
    /// - Returns: A configured RenderConfig instance, or nil if required parameters are missing
    static func fromArguments(_ arguments: [String: Any]?) -> RenderConfig? {
        guard let args = arguments else {
            return nil
        }
        
        // Parse video clips (required for video rendering)
        var videoClips: [VideoClip] = []
        if let videoClipsRaw = args["videoClips"] as? [[String: Any]] {
            videoClips = videoClipsRaw.compactMap { clipMap in
                guard let inputPath = clipMap["inputPath"] as? String else {
                    return nil
                }
                return VideoClip(
                    inputPath: inputPath,
                    startUs: (clipMap["startUs"] as? NSNumber)?.int64Value,
                    endUs: (clipMap["endUs"] as? NSNumber)?.int64Value
                )
            }
        }
        
        // Parse color matrix list
        var colorMatrixList: [[Double]] = []
        if let matricesRaw = args["colorMatrixList"] as? [[NSNumber]] {
            colorMatrixList = matricesRaw.map { matrix in
                matrix.map { $0.doubleValue }
            }
        }
        
        return RenderConfig(
            videoClips: videoClips,
            imageData: args["imageBytes"] as? Data,
            inputFormat: args["inputFormat"] as? String ?? "mp4",
            outputFormat: args["outputFormat"] as? String ?? "mp4",
            outputPath: args["outputPath"] as? String,
            rotateTurns: args["rotateTurns"] as? Int,
            flipX: args["flipX"] as? Bool ?? false,
            flipY: args["flipY"] as? Bool ?? false,
            cropWidth: args["cropWidth"] as? Int,
            cropHeight: args["cropHeight"] as? Int,
            cropX: args["cropX"] as? Int,
            cropY: args["cropY"] as? Int,
            scaleX: (args["scaleX"] as? NSNumber)?.floatValue,
            scaleY: (args["scaleY"] as? NSNumber)?.floatValue,
            bitrate: args["bitrate"] as? Int,
            enableAudio: args["enableAudio"] as? Bool ?? true,
            playbackSpeed: (args["playbackSpeed"] as? NSNumber)?.floatValue,
            colorMatrixList: colorMatrixList,
            blur: (args["blur"] as? NSNumber)?.doubleValue,
            customAudioPath: args["customAudioPath"] as? String,
            originalAudioVolume: (args["originalAudioVolume"] as? NSNumber)?.floatValue,
            customAudioVolume: (args["customAudioVolume"] as? NSNumber)?.floatValue
        )
    }
}
