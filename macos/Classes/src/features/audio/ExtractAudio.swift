import AVFoundation
import Foundation
import FlutterMacOS

/// Exception thrown when no audio track is found in the video file.
class NoAudioTrackException: NSError {
    init() {
        super.init(
            domain: "ExtractAudio",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "No audio track found in video"]
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Service for extracting audio from video files using AVFoundation.
///
/// This class handles the audio extraction pipeline:
/// - Extracts audio track from video file
/// - Supports trimming (start/end time)
/// - Supports multiple output formats (M4A, AAC, CAF)
/// - Provides progress tracking during extraction
/// - Supports cancellation of active extraction jobs
class ExtractAudio {
    
    /// Extracts audio from a video file asynchronously.
    ///
    /// This method uses AVAssetExportSession for fast Passthrough export.
    ///
    /// - Parameters:
    ///   - config: Complete extraction configuration
    ///   - onProgress: Callback invoked with progress updates (0.0 to 1.0)
    ///   - onComplete: Callback invoked on success with output bytes (nil if saved to file)
    ///   - onError: Callback invoked if extraction fails
    /// - Returns: Cancellation handle that can be used to stop the extraction
    static func extract(
        config: AudioExtractConfig,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (FlutterStandardTypedData?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> AudioExtractJobHandle {
        
        var exportSession: AVAssetExportSession?
        var progressTimer: Timer?
        var isCancelled = false
        
        // Execute extraction on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Load source video asset
                let sourceURL = URL(fileURLWithPath: config.inputPath)
                let asset = AVURLAsset(url: sourceURL)
                
                // Determine output file location
                let outputURL: URL
                if let outputPath = config.outputPath {
                    outputURL = URL(fileURLWithPath: outputPath)
                } else {
                    let tempDir = FileManager.default.temporaryDirectory
                    let filename = "audio_\(Date().timeIntervalSince1970).\(config.getOutputExtension())"
                    outputURL = tempDir.appendingPathComponent(filename)
                }
                
                // Remove existing file if present
                try? FileManager.default.removeItem(at: outputURL)
                
                // Determine output file type based on extension
                let fileExtension = outputURL.pathExtension.lowercased()
                let outputFileType: AVFileType
                
                switch fileExtension {
                case "m4a":
                    outputFileType = .m4a
                case "aac":
                    outputFileType = .m4a
                case "caf":
                    outputFileType = .caf
                default:
                    outputFileType = .m4a
                }
                
                // Create export session with audio-only preset
                guard let session = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetPassthrough
                ) else {
                    throw NSError(
                        domain: "ExtractAudio",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]
                    )
                }
                
                exportSession = session
                session.outputURL = outputURL
                session.outputFileType = outputFileType
                
                // Configure to export only audio tracks
                let audioTracks = asset.tracks(withMediaType: .audio)
                guard !audioTracks.isEmpty else {
                    throw NoAudioTrackException()
                }
                
                // Apply time range if trimming is requested
                if let startUs = config.startUs, let endUs = config.endUs {
                    let startTime = CMTime(value: startUs, timescale: 1_000_000)
                    let endTime = CMTime(value: endUs, timescale: 1_000_000)
                    let duration = CMTimeSubtract(endTime, startTime)
                    session.timeRange = CMTimeRange(start: startTime, duration: duration)
                } else if let startUs = config.startUs {
                    let startTime = CMTime(value: startUs, timescale: 1_000_000)
                    let duration = CMTimeSubtract(asset.duration, startTime)
                    session.timeRange = CMTimeRange(start: startTime, duration: duration)
                } else if let endUs = config.endUs {
                    let endTime = CMTime(value: endUs, timescale: 1_000_000)
                    session.timeRange = CMTimeRange(start: .zero, duration: endTime)
                }
                
                // Start progress tracking on main thread
                DispatchQueue.main.async {
                    onProgress(0.0)
                    
                    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        guard !isCancelled else { return }
                        let progress = Double(session.progress)
                        onProgress(progress)
                    }
                }
                
                // Start export
                session.exportAsynchronously {
                    DispatchQueue.main.async {
                        progressTimer?.invalidate()
                        progressTimer = nil
                    }
                    
                    // Check cancellation
                    if isCancelled {
                        try? FileManager.default.removeItem(at: outputURL)
                        DispatchQueue.main.async {
                            onError(NSError(
                                domain: "ExtractAudio",
                                code: -3,
                                userInfo: [NSLocalizedDescriptionKey: "Extraction was cancelled"]
                            ))
                        }
                        return
                    }
                    
                    // Check export status - handle on background queue
                    DispatchQueue.global(qos: .userInitiated).async {
                        switch session.status {
                        case .completed:
                            do {
                                if config.outputPath != nil {
                                    // File output - return nil
                                    DispatchQueue.main.async {
                                        onProgress(1.0)
                                        onComplete(nil)
                                    }
                                } else {
                                    // Memory output - read file and return bytes (on background thread)
                                    let data = try Data(contentsOf: outputURL)
                                    let flutterData = FlutterStandardTypedData(bytes: data)
                                    
                                    // Clean up temporary file
                                    try? FileManager.default.removeItem(at: outputURL)
                                    
                                    DispatchQueue.main.async {
                                        onProgress(1.0)
                                        onComplete(flutterData)
                                    }
                                }
                            } catch {
                                try? FileManager.default.removeItem(at: outputURL)
                                DispatchQueue.main.async {
                                    onError(error)
                                }
                            }
                            
                        case .failed:
                            try? FileManager.default.removeItem(at: outputURL)
                            let error = session.error ?? NSError(
                                domain: "ExtractAudio",
                                code: -4,
                                userInfo: [NSLocalizedDescriptionKey: "Export failed with unknown error"]
                            )
                            DispatchQueue.main.async {
                                onError(error)
                            }
                            
                        case .cancelled:
                            try? FileManager.default.removeItem(at: outputURL)
                            DispatchQueue.main.async {
                                onError(NSError(
                                    domain: "ExtractAudio",
                                    code: -5,
                                    userInfo: [NSLocalizedDescriptionKey: "Export was cancelled"]
                                ))
                            }
                            
                        default:
                            try? FileManager.default.removeItem(at: outputURL)
                            DispatchQueue.main.async {
                                onError(NSError(
                                    domain: "ExtractAudio",
                                    code: -6,
                                    userInfo: [NSLocalizedDescriptionKey: "Export ended with unexpected status: \(session.status.rawValue)"]
                                ))
                            }
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    progressTimer?.invalidate()
                    onError(error)
                }
            }
        }
        
        // Return cancellation handle
        return {
            isCancelled = true
            exportSession?.cancelExport()
            DispatchQueue.main.async {
                progressTimer?.invalidate()
            }
        }
    }
}
