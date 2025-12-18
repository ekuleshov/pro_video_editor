import AVFoundation
import Foundation

/// Builder class for creating video sequences in compositions.
///
/// Handles multiple video clips, audio tracks, volume control,
/// and composition assembly.
internal class VideoSequenceBuilder {
    
    private let videoClips: [VideoClip]
    private var enableAudio: Bool = true
    private var originalAudioVolume: Float = 1.0
    
    /// Initializes builder with video clips.
    ///
    /// - Parameter videoClips: Array of video clips to process
    init(videoClips: [VideoClip]) {
        self.videoClips = videoClips
    }
    
    /// Enables or disables audio in the output.
    ///
    /// - Parameter enabled: If true, includes original audio from video clips
    /// - Returns: Self for chaining
    func setEnableAudio(_ enabled: Bool) -> VideoSequenceBuilder {
        self.enableAudio = enabled
        return self
    }
    
    /// Sets the volume for original video audio.
    ///
    /// - Parameter volume: Volume multiplier (0.0 to 1.0+)
    /// - Returns: Self for chaining
    func setOriginalAudioVolume(_ volume: Float) -> VideoSequenceBuilder {
        self.originalAudioVolume = volume
        return self
    }
    
    /// Calculates total duration of all video clips combined.
    ///
    /// - Returns: Total duration as CMTime
    func calculateTotalDuration() async -> CMTime {
        var totalDuration = CMTime.zero
        
        for clip in videoClips {
            let clipDuration = await calculateClipDuration(clip)
            totalDuration = CMTimeAdd(totalDuration, clipDuration)
        }
        
        let durationMs = Int(totalDuration.seconds * 1000)
        print("🔍 Total video duration: \(durationMs) ms")
        return totalDuration
    }
    
    /// Calculates duration of a single clip considering trimming.
    private func calculateClipDuration(_ clip: VideoClip) async -> CMTime {
        let url = URL(fileURLWithPath: clip.inputPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .zero
        }
        
        let asset = AVURLAsset(url: url)
        let assetDuration: CMTime
        
        if #available(macOS 13.0, *) {
            assetDuration = (try? await asset.load(.duration)) ?? .zero
        } else {
            assetDuration = asset.duration
        }
        
        let startTime = clip.startUs.map { CMTime(value: $0, timescale: 1_000_000) } ?? .zero
        let endTime = clip.endUs.map { CMTime(value: $0, timescale: 1_000_000) } ?? assetDuration
        
        return CMTimeSubtract(endTime, startTime)
    }
    
    /// Builds the video composition with all clips.
    ///
    /// - Parameter composition: Composition to build into
    /// - Returns: Tuple containing video track, audio tracks, render size, and frame rate
    func build(in composition: AVMutableComposition) async throws -> VideoSequenceResult {
        guard !videoClips.isEmpty else {
            throw NSError(
                domain: "VideoSequenceBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Video clips cannot be empty"]
            )
        }
        
        print("🎬 Building video sequence with \(videoClips.count) clips")
        print("🔊 Audio enabled: \(enableAudio)")
        
        var totalDuration = CMTime.zero
        var maxRenderSize = CGSize.zero
        var maxFrameRate: Float = 30.0
        var firstClipTransform = CGAffineTransform.identity
        var originalAudioTracks: [AVMutableCompositionTrack] = []
        
        // Create single video track for all clips
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(
                domain: "VideoSequenceBuilder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create video track"]
            )
        }
        
        // Process each video clip
        for (index, clip) in videoClips.enumerated() {
            print("📹 Processing clip \(index): \(clip.inputPath)")
            
            let url = URL(fileURLWithPath: clip.inputPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("❌ ERROR: Video file does not exist: \(clip.inputPath)")
                throw NSError(
                    domain: "VideoSequenceBuilder",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Video file does not exist: \(clip.inputPath)"]
                )
            }
            
            let asset = AVURLAsset(url: url)
            
            // Load video track
            let videoTrack = try await MediaInfoExtractor.loadVideoTrack(from: asset)
            
            // Get video properties
            let naturalSize = videoTrack.naturalSize
            let nominalFrameRate = videoTrack.nominalFrameRate
            let preferredTransform = videoTrack.preferredTransform
            
            // Calculate corrected size (accounting for rotation)
            let displaySize = naturalSize.applying(preferredTransform)
            let correctedSize = CGSize(
                width: abs(displaySize.width),
                height: abs(displaySize.height)
            )
            
            // Update max render size
            if correctedSize.width > maxRenderSize.width || correctedSize.height > maxRenderSize.height {
                maxRenderSize = correctedSize
            }
            
            // Update max frame rate
            if nominalFrameRate > maxFrameRate {
                maxFrameRate = nominalFrameRate
            }
            
            // Store the transform from the first clip
            if index == 0 {
                firstClipTransform = preferredTransform
            }
            
            // Calculate time range for this clip
            let clipTimeRange = calculateTimeRange(for: clip, from: asset)
            let clipDuration = clipTimeRange.duration
            
            // Insert video clip into the composition track
            try compositionVideoTrack.insertTimeRange(
                clipTimeRange,
                of: videoTrack,
                at: totalDuration
            )
            
            // Add audio track if enabled
            if enableAudio {
                if let audioTrack = try? await MediaInfoExtractor.loadAudioTrack(from: asset) {
                    if let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) {
                        try? compositionAudioTrack.insertTimeRange(
                            clipTimeRange,
                            of: audioTrack,
                            at: totalDuration
                        )
                        originalAudioTracks.append(compositionAudioTrack)
                        
                        if originalAudioVolume != 1.0 {
                            print("🔊 Setting original audio volume to \(originalAudioVolume)")
                        }
                    }
                }
            }
            
            totalDuration = CMTimeAdd(totalDuration, clipDuration)
            print("✅ Clip \(index) added, duration: \(clipDuration.seconds)s, total: \(totalDuration.seconds)s")
        }
        
        print("📊 Total video duration: \(totalDuration.seconds)s")
        print("📐 Max render size: \(maxRenderSize)")
        
        return VideoSequenceResult(
            videoTrack: compositionVideoTrack,
            audioTracks: originalAudioTracks,
            totalDuration: totalDuration,
            renderSize: maxRenderSize,
            frameRate: maxFrameRate,
            transform: firstClipTransform
        )
    }
    
    /// Calculates time range for a clip considering start/end trimming.
    private func calculateTimeRange(for clip: VideoClip, from asset: AVAsset) -> CMTimeRange {
        let startTime: CMTime
        let endTime: CMTime
        
        if let startUs = clip.startUs {
            startTime = CMTime(value: startUs, timescale: 1_000_000)
        } else {
            startTime = .zero
        }
        
        if let endUs = clip.endUs {
            endTime = CMTime(value: endUs, timescale: 1_000_000)
        } else {
            endTime = asset.duration
        }
        
        let duration = CMTimeSubtract(endTime, startTime)
        return CMTimeRange(start: startTime, duration: duration)
    }
}

/// Result of building a video sequence.
internal struct VideoSequenceResult {
    let videoTrack: AVMutableCompositionTrack
    let audioTracks: [AVMutableCompositionTrack]
    let totalDuration: CMTime
    let renderSize: CGSize
    let frameRate: Float
    let transform: CGAffineTransform
}
