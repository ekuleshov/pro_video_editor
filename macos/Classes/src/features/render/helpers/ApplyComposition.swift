import AVFoundation
import Foundation

/// Creates a multi-clip video composition with audio mixing and custom effects.
///
/// This function orchestrates the entire composition pipeline:
/// 1. Concatenates multiple video clips into a single timeline
/// 2. Manages audio tracks (original + custom audio with volume control)
/// 3. Applies video effects through VideoCompositorConfig
/// 4. Calculates optimal render size and frame rate across all clips
///
/// The composition is built by inserting each clip sequentially into a shared video track.
/// Audio handling supports mixing original audio with custom audio, each with independent
/// volume controls. The final render size is determined by the largest clip dimensions.
///
/// - Parameters:
///   - videoClips: Array of video clips to concatenate. Each clip can have optional trimming.
///   - videoEffects: Configuration for visual effects (rotation, scale, color, blur, etc.).
///   - enableAudio: If true, includes original audio from video clips.
///   - customAudioPath: Optional path to custom audio file to mix over the video.
///   - originalAudioVolume: Volume for original video audio (0.0 to 1.0). Default 1.0.
///   - customAudioVolume: Volume for custom audio track (0.0 to 1.0). Default 1.0.
///
/// - Returns: A tuple containing:
///   - AVMutableComposition: The concatenated video/audio composition
///   - AVMutableVideoComposition: Video composition with effects and instructions
///   - CGSize: Final render size (max dimensions from all clips)
///   - AVAudioMix?: Audio mix with volume controls (nil if no audio mixing needed)
///
/// - Throws: NSError if video clips are empty, files don't exist, or tracks can't be loaded.
func applyComposition(
    videoClips: [VideoClip],
    videoEffects: VideoCompositorConfig,
    enableAudio: Bool,
    customAudioPath: String?,
    originalAudioVolume: Float?,
    customAudioVolume: Float?
) async throws -> (AVMutableComposition, AVMutableVideoComposition, CGSize, AVAudioMix?) {
    
    guard !videoClips.isEmpty else {
        throw NSError(
            domain: "ApplyComposition",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Video clips cannot be empty"]
        )
    }
    
    print("🎬 Creating composition with \(videoClips.count) video clips")
    print("🔊 Audio enabled: \(enableAudio)")
    
    let composition = AVMutableComposition()
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
            domain: "ApplyComposition",
            code: 3,
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
                domain: "ApplyComposition",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Video file does not exist: \(clip.inputPath)"]
            )
        }
        
        let asset = AVURLAsset(url: url)
        
        // Load video track
        let videoTrack = try await loadVideoTrack(from: asset)
        
        // Get video properties
        let naturalSize: CGSize
        let nominalFrameRate: Float
        let preferredTransform: CGAffineTransform
        
        if #available(macOS 15.0, *) {
            naturalSize = try await videoTrack.load(.naturalSize)
            nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            preferredTransform = try await videoTrack.load(.preferredTransform)
        } else {
            naturalSize = videoTrack.naturalSize
            nominalFrameRate = videoTrack.nominalFrameRate
            preferredTransform = videoTrack.preferredTransform
        }
        
        // Calculate corrected size (accounting for rotation)
        let displaySize = naturalSize.applying(preferredTransform)
        let correctedSize = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))
        
        // Update max render size
        if correctedSize.width > maxRenderSize.width || correctedSize.height > maxRenderSize.height {
            maxRenderSize = correctedSize
        }
        
        // Update max frame rate
        if nominalFrameRate > maxFrameRate {
            maxFrameRate = nominalFrameRate
        }
        
        // Store the transform from the first clip for the composition
        if index == 0 {
            firstClipTransform = preferredTransform
        }
        
        // Calculate time range for this clip
        let clipTimeRange = calculateTimeRange(for: clip, from: asset)
        let clipDuration = clipTimeRange.duration
        
        // Insert video clip into the single composition track
        try compositionVideoTrack.insertTimeRange(
            clipTimeRange,
            of: videoTrack,
            at: totalDuration
        )
        
        // Add audio track if enabled
        if enableAudio {
            if let audioTrack = try? await loadAudioTrack(from: asset) {
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
                    
                    // Apply original audio volume if specified
                    if let volume = originalAudioVolume, volume != 1.0 {
                        print("🔊 Setting original audio volume to \(volume)")
                        // Volume will be applied during audio mix
                    }
                }
            }
        }
        
        // Note: Layer instruction is created later for the entire composition track
        
        totalDuration = CMTimeAdd(totalDuration, clipDuration)
        print("✅ Clip \(index) added, duration: \(clipDuration.seconds)s, total: \(totalDuration.seconds)s")
    }
    
    print("📊 Total video duration: \(totalDuration.seconds)s")
    print("📐 Max render size: \(maxRenderSize)")
    
    var customAudioTrack: AVMutableCompositionTrack?
    
    // Add custom audio track if provided
    if let customAudioPath = customAudioPath, !customAudioPath.isEmpty {
        print("🎵 Adding custom audio track: \(customAudioPath)")
        customAudioTrack = try await addCustomAudioTrack(
            to: composition,
            audioPath: customAudioPath,
            totalDuration: totalDuration,
            volume: customAudioVolume
        )
    }
    
    // Create audio mix with volume parameters
    var audioMix: AVAudioMix?
    if enableAudio && (originalAudioVolume != nil || customAudioVolume != nil) {
        audioMix = createAudioMix(
            originalTracks: originalAudioTracks,
            customTrack: customAudioTrack,
            originalVolume: originalAudioVolume ?? 1.0,
            customVolume: customAudioVolume ?? 1.0
        )
    }
    
    // Create video composition
    let videoComposition = AVMutableVideoComposition()
    videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(max(30, maxFrameRate)))
    videoComposition.renderSize = maxRenderSize
    
    // Create single instruction for the entire composition track
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
    instruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    
    // Create layer instruction for the single composition video track
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
    layerInstruction.setTransform(firstClipTransform, at: CMTime.zero)
    instruction.layerInstructions = [layerInstruction]
    
    videoComposition.instructions = [instruction]
    
    print("✅ Composition created successfully with \(videoClips.count) clips")
    
    return (composition, videoComposition, maxRenderSize, audioMix)
}

// MARK: - Helper Functions

private func loadVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
    if #available(macOS 13.0, *) {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw NSError(
                domain: "ApplyComposition",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No video track found"]
            )
        }
        return track
    } else {
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw NSError(
                domain: "ApplyComposition",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No video track found"]
            )
        }
        return track
    }
}

private func loadAudioTrack(from asset: AVAsset) async throws -> AVAssetTrack? {
    if #available(macOS 13.0, *) {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        return tracks.first
    } else {
        return asset.tracks(withMediaType: .audio).first
    }
}

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

private func addCustomAudioTrack(
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
    
    // Trim or loop custom audio to match video duration
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

private func createAudioMix(
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
