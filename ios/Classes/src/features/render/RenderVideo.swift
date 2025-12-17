import AVFoundation
import CoreImage
import Foundation

/// Service for rendering video with applied effects and transformations.
///
/// This class handles the complete video rendering pipeline using AVFoundation:
/// - Applies visual effects (rotation, flip, crop, scale, color matrix, blur)
/// - Manages audio mixing (original audio volume + custom audio track)
/// - Supports playback speed adjustment and trimming
/// - Provides progress tracking during rendering
/// - Supports cancellation of active render jobs
///
/// All rendering operations are performed asynchronously on a dedicated queue.
class RenderVideo {
    static let queue = DispatchQueue(label: "RenderVideoQueue")

    // MARK: - Public Methods
    
    /// Starts an asynchronous video render job using RenderConfig.
    ///
    /// This method configures and starts an AVFoundation export session to process
    /// the video with the specified effects. The operation runs asynchronously and
    /// provides callbacks for progress updates, completion, and errors.
    ///
    /// Note: iOS currently supports single video clip rendering.
    ///
    /// - Parameters:
    ///   - config: Complete render configuration including input, output, and effects
    ///   - onProgress: Callback invoked with progress updates (0.0 to 1.0)
    ///   - onComplete: Callback invoked on success with output bytes (nil if saved to file)
    ///   - onError: Callback invoked if rendering fails
    /// - Returns: RenderJobHandle that can be used to cancel the render job
    @discardableResult
    static func render(
        config: RenderConfig,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Data?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> RenderJobHandle {
        let handle = RenderJobHandle()
        queue.async {
            let renderTask = Task {
                // For iOS, we currently support single video clip
                let inputPath = config.videoClips.first?.inputPath ?? ""
                let startUs = config.videoClips.first?.startUs ?? config.startUs
                let endUs = config.videoClips.first?.endUs ?? config.endUs
                
                var inputURL: URL!
                var outputURL: URL!

                let finalize: () -> Void = {
                    try? cleanup(outputPath == nil ? [outputURL] : [])
                }

                let handleCompletion: (Result<Data?, Error>) -> Void = { result in
                    switch result {
                    case .success(let data): onComplete(data)
                    case .failure(let error): onError(error)
                    }
                    finalize()
                }

                do {
                    inputURL = URL(fileURLWithPath: inputPath)
                    if let outputPath = config.outputPath {
                        outputURL = URL(fileURLWithPath: outputPath)
                    } else {
                        outputURL = temporaryURL(for: config.outputFormat)
                    }

                    let asset = AVURLAsset(url: inputURL)
                    let composition = AVMutableComposition()
                    var effectsConfig = VideoCompositorConfig()

                    let videoTrack = try await loadVideoTrack(from: asset)

                    let timeRange = await applyTrim(asset: asset, startUs: startUs, endUs: endUs)

                    let videoCompositionTrack = try insertVideoTrack(
                        into: composition,
                        from: videoTrack,
                        timeRange: timeRange
                    )

                    // Apply audio track
                    var originalAudioTracks: [AVMutableCompositionTrack] = []
                    if config.enableAudio {
                        if let audioTrack = try? await loadAudioTrack(from: asset) {
                            if let compositionAudioTrack = composition.addMutableTrack(
                                withMediaType: .audio,
                                preferredTrackID: kCMPersistentTrackID_Invalid
                            ) {
                                try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                                originalAudioTracks.append(compositionAudioTrack)
                            }
                        }
                    }
                    
                    // Add custom audio track if provided
                    var customAudioTrack: AVMutableCompositionTrack?
                    if let customAudioPath = config.customAudioPath, !customAudioPath.isEmpty {
                        print("🎵 Adding custom audio track: \(customAudioPath)")
                        customAudioTrack = try await addCustomAudioTrack(
                            to: composition,
                            audioPath: customAudioPath,
                            totalDuration: composition.duration,
                            volume: config.customAudioVolume
                        )
                    }
                    
                    applyPlaybackSpeed(composition: composition, speed: config.playbackSpeed)

                    // Enhanced video composition with orientation handling
                    let (videoComposition, correctedNaturalSize, preferredTransform) =
                        try await createVideoComposition(
                            asset: asset,
                            track: videoCompositionTrack,
                            duration: composition.duration
                        )

                    let videoRotationDegrees = extractRotationFromTransform(preferredTransform)
                    effectsConfig.videoRotationDegrees = videoRotationDegrees
                    effectsConfig.shouldApplyOrientationCorrection = abs(videoRotationDegrees) > 1.0
                    effectsConfig.originalNaturalSize = videoTrack.naturalSize

                    let croppedSize = applyCrop(
                        config: &effectsConfig,
                        naturalSize: correctedNaturalSize,
                        rotateTurns: config.rotateTurns,
                        cropX: config.cropX,
                        cropY: config.cropY,
                        cropWidth: config.cropWidth,
                        cropHeight: config.cropHeight
                    )

                    applyRotation(config: &effectsConfig, rotateTurns: config.rotateTurns)
                    applyFlip(config: &effectsConfig, flipX: config.flipX, flipY: config.flipY)
                    applyScale(config: &effectsConfig, scaleX: config.scaleX, scaleY: config.scaleY)
                    applyColorMatrix(
                        config: &effectsConfig, to: videoComposition, matrixList: config.colorMatrixList)
                    applyBlur(config: &effectsConfig, sigma: config.blur)
                    applyImageLayer(config: &effectsConfig, imageData: config.imageData)

                    var finalRenderSize = videoComposition.renderSize

                    // Only update renderSize if cropping was actually applied
                    if config.cropWidth != nil || config.cropHeight != nil {
                        finalRenderSize = croppedSize
                    } else {
                        if let rotateTurns = config.rotateTurns {
                            let normalizedRotation = (rotateTurns % 4 + 4) % 4
                            if normalizedRotation == 1 || normalizedRotation == 3 {
                                finalRenderSize = CGSize(
                                    width: finalRenderSize.height,
                                    height: finalRenderSize.width
                                )
                            }
                        }
                    }

                    let effectiveScaleX = config.scaleX ?? 1.0
                    let effectiveScaleY = config.scaleY ?? 1.0

                    if effectiveScaleX != 1.0 || effectiveScaleY != 1.0 {
                        finalRenderSize = CGSize(
                            width: finalRenderSize.width * CGFloat(effectiveScaleX),
                            height: finalRenderSize.height * CGFloat(effectiveScaleY)
                        )
                    } else if effectsConfig.scaleX != 1.0 || effectsConfig.scaleY != 1.0 {
                        finalRenderSize = CGSize(
                            width: finalRenderSize.width * effectsConfig.scaleX,
                            height: finalRenderSize.height * effectsConfig.scaleY
                        )
                    }

                    videoComposition.renderSize = finalRenderSize

                    let compositorClass = makeVideoCompositorSubclass(with: effectsConfig)
                    videoComposition.customVideoCompositorClass = compositorClass

                    let preset = applyBitrate(requestedBitrate: config.bitrate)

                    // Create audio mix with volume parameters
                    var audioMix: AVAudioMix?
                    if config.enableAudio && (config.originalAudioVolume != nil || config.customAudioVolume != nil) {
                        audioMix = createAudioMix(
                            originalTracks: originalAudioTracks,
                            customTrack: customAudioTrack,
                            originalVolume: config.originalAudioVolume ?? 1.0,
                            customVolume: config.customAudioVolume ?? 1.0
                        )
                    }

                    let export = try prepareExportSession(
                        composition: composition,
                        videoComposition: videoComposition,
                        outputURL: outputURL,
                        outputFormat: config.outputFormat,
                        preset: preset,
                        audioMix: audioMix
                    )
                    handle.attach(export: export)

                    try await monitorExportProgress(export, onProgress: onProgress)

                    if config.outputPath != nil {
                        handleCompletion(.success(nil))
                    } else {
                        let data = try Data(contentsOf: outputURL)
                        handleCompletion(.success(data))
                    }
                } catch {
                    handleCompletion(.failure(error))
                }
            }
            handle.attach(task: renderTask)
        }

        return handle
    }

    // MARK: - Helper Methods

    private static func makeVideoCompositorSubclass(with config: VideoCompositorConfig)
        -> AVVideoCompositing.Type
    {
        class CustomCompositor: VideoCompositor {}
        CustomCompositor.config = config
        return CustomCompositor.self
    }

    private static func uniqueFilename(prefix: String, extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let timestamp = formatter.string(from: Date())
        return "\(prefix)_\(timestamp).\(ext)"
    }

    private static func writeInputVideo(_ data: Data, format: String) throws -> URL {
        let filename = uniqueFilename(prefix: "input", extension: format)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    private static func temporaryURL(for format: String) -> URL {
        let filename = uniqueFilename(prefix: "output", extension: format)
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private static func loadVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        if #available(iOS 15.0, *) {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw NSError(
                    domain: "RenderVideo", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No video track found"])
            }
            return track
        } else {
            guard let track = asset.tracks(withMediaType: .video).first else {
                throw NSError(
                    domain: "RenderVideo", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No video track found"])
            }
            return track
        }
    }

    private static func insertVideoTrack(
        into composition: AVMutableComposition,
        from videoTrack: AVAssetTrack,
        timeRange: CMTimeRange
    ) throws -> AVMutableCompositionTrack {
        guard
            let track = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw NSError(
                domain: "RenderVideo", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create video track"])
        }
        try track.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        return track
    }

    private static func createVideoComposition(
        asset: AVAsset,
        track: AVCompositionTrack,
        duration: CMTime
    ) async throws -> (AVMutableVideoComposition, CGSize, CGAffineTransform) {
        // Get the original video track to extract properties
        let originalVideoTracks: [AVAssetTrack]
        if #available(iOS 15.0, *) {
            originalVideoTracks = try await asset.loadTracks(withMediaType: .video)
        } else {
            originalVideoTracks = asset.tracks(withMediaType: .video)
        }

        guard let originalVideoTrack = originalVideoTracks.first else {
            throw NSError(
                domain: "RenderVideo", code: 150,
                userInfo: [NSLocalizedDescriptionKey: "No original video track found"])
        }

        // Get video properties
        let naturalSize: CGSize
        let nominalFrameRate: Float
        let preferredTransform: CGAffineTransform

        if #available(iOS 15.0, *) {
            naturalSize = try await originalVideoTrack.load(.naturalSize)
            nominalFrameRate = try await originalVideoTrack.load(.nominalFrameRate)
            preferredTransform = try await originalVideoTrack.load(.preferredTransform)
        } else {
            naturalSize = originalVideoTrack.naturalSize
            nominalFrameRate = originalVideoTrack.nominalFrameRate
            preferredTransform = originalVideoTrack.preferredTransform
        }

        // Calculate display size after applying transform (handles rotation)
        let displaySize = naturalSize.applying(preferredTransform)
        let correctedSize = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))

        let composition = AVMutableVideoComposition()
        composition.frameDuration = CMTime(value: 1, timescale: Int32(max(30, nominalFrameRate)))
        composition.renderSize = correctedSize

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        return (composition, correctedSize, preferredTransform)
    }

    private static func extractRotationFromTransform(_ transform: CGAffineTransform) -> Double {
        let rotationAngle = atan2(transform.b, transform.a)
        return rotationAngle * 180 / Double.pi
    }

    private static func prepareExportSession(
        composition: AVAsset,
        videoComposition: AVVideoComposition,
        outputURL: URL,
        outputFormat: String,
        preset: String,
        audioMix: AVAudioMix?
    ) throws -> AVAssetExportSession {
        guard let export = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw NSError(
                domain: "RenderVideo", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Export session creation failed"])
        }
        export.outputURL = outputURL
        export.outputFileType = mapFormatToMimeType(format: outputFormat)
        export.videoComposition = videoComposition
        export.audioMix = audioMix
        return export
    }

    private static func monitorExportProgress(
        _ export: AVAssetExportSession,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let updateInterval: TimeInterval = 0.2
        /*  if #available(macOS 15.0, *) {
        
             for try await state in export.states(updateInterval: updateInterval) {
                 switch state {
                 case .waiting:
                     break
                 case .pending:
                     break
                 case .exporting(let progress):
                     onProgress(progress.fractionCompleted)
                 @unknown default:
                     throw NSError(
                         domain: "RenderVideo", code: 6,
                         userInfo: [NSLocalizedDescriptionKey: "Unknown export state encountered"]
                     )
                 }
             }
         } else { */
        let intervalNs = UInt64(updateInterval * 1_000_000_000)
        export.exportAsynchronously {}
        while export.status == .waiting || export.status == .exporting {
            if export.status == .exporting {
                let normalizedProgress = min(max(export.progress, 0), 1.0)
                onProgress(Double(normalizedProgress))
            }
            try await Task.sleep(nanoseconds: intervalNs)
        }

        guard export.status == .completed else {
            throw export.error
                ?? NSError(
                    domain: "RenderVideo", code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Export failed with status \(export.status.rawValue)"
                    ])
        }
        /*  } */
    }

    private static func cleanup(_ urls: [URL]) throws {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private static func loadAudioTrack(from asset: AVAsset) async throws -> AVAssetTrack? {
        if #available(iOS 15.0, *) {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return tracks.first
        } else {
            return asset.tracks(withMediaType: .audio).first
        }
    }
    
    private static func addCustomAudioTrack(
        to composition: AVMutableComposition,
        audioPath: String,
        totalDuration: CMTime,
        volume: Float?
    ) async throws -> AVMutableCompositionTrack? {
        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("⚠️ Custom audio file does not exist: \(audioPath)")
            return nil
        }
        
        let audioAsset = AVURLAsset(url: audioURL)
        
        guard let audioTrack = try? await loadAudioTrack(from: audioAsset),
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            print("⚠️ Failed to add custom audio track")
            return nil
        }
        
        // Loop custom audio to match video duration
        let audioDuration = audioAsset.duration
        
        if audioDuration > totalDuration {
            // Trim audio to match video duration
            let timeRange = CMTimeRange(start: .zero, duration: totalDuration)
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            print("✂️ Custom audio trimmed to \(totalDuration.seconds)s")
        } else {
            // Loop audio to match video duration
            var currentTime = CMTime.zero
            var loopCount = 0
            
            while currentTime < totalDuration {
                let remainingDuration = CMTimeSubtract(totalDuration, currentTime)
                let insertDuration = CMTimeMinimum(audioDuration, remainingDuration)
                let timeRange = CMTimeRange(start: .zero, duration: insertDuration)
                
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: currentTime)
                currentTime = CMTimeAdd(currentTime, insertDuration)
                loopCount += 1
            }
            
            print("🔄 Custom audio looped \(loopCount) times to match \(totalDuration.seconds)s duration")
        }
        
        if let volume = volume, volume != 1.0 {
            print("🔊 Custom audio volume: \(volume)")
        }
        
        return compositionAudioTrack
    }
    
    private static func createAudioMix(
        originalTracks: [AVMutableCompositionTrack],
        customTrack: AVMutableCompositionTrack?,
        originalVolume: Float,
        customVolume: Float
    ) -> AVAudioMix {
        var audioMixInputParameters: [AVMutableAudioMixInputParameters] = []
        
        // Apply volume to original audio tracks
        for track in originalTracks {
            let inputParameters = AVMutableAudioMixInputParameters(track: track)
            inputParameters.setVolume(originalVolume, at: .zero)
            audioMixInputParameters.append(inputParameters)
            print("🔊 Applied volume \(originalVolume) to original audio track")
        }
        
        // Apply volume to custom audio track
        if let customTrack = customTrack {
            let inputParameters = AVMutableAudioMixInputParameters(track: customTrack)
            inputParameters.setVolume(customVolume, at: .zero)
            audioMixInputParameters.append(inputParameters)
            print("🔊 Applied volume \(customVolume) to custom audio track")
        }
        
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixInputParameters
        
        return audioMix
    }
}

final class RenderJobHandle {
    private let lock = NSLock()
    private var exportSession: AVAssetExportSession?
    private var renderTask: Task<Void, Never>?
    private var canceled = false

    func attach(export: AVAssetExportSession) {
        lock.lock()
        defer { lock.unlock() }
        exportSession = export
        if canceled {
            export.cancelExport()
        }
    }

    func attach(task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        renderTask = task
        if canceled {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        canceled = true
        let session = exportSession
        let task = renderTask
        lock.unlock()

        task?.cancel()
        session?.cancelExport()
    }
}
