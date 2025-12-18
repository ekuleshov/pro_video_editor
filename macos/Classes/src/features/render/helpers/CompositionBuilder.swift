import AVFoundation
import Foundation

/// Main builder class for creating video compositions from render configurations.
///
/// Orchestrates video sequences, custom audio tracks, and audio mixing.
/// This class delegates the actual work to specialized builders
/// (VideoSequenceBuilder, AudioSequenceBuilder) following the Builder pattern.
internal class CompositionBuilder {
    
    private let videoClips: [VideoClip]
    private let videoEffects: VideoCompositorConfig
    private var enableAudio: Bool = true
    private var customAudioPath: String?
    private var originalAudioVolume: Float = 1.0
    private var customAudioVolume: Float = 1.0
    
    /// Initializes builder with configuration.
    ///
    /// - Parameters:
    ///   - videoClips: Array of video clips to process
    ///   - videoEffects: Video effect configuration
    init(videoClips: [VideoClip], videoEffects: VideoCompositorConfig) {
        self.videoClips = videoClips
        self.videoEffects = videoEffects
    }
    
    /// Enables or disables audio.
    ///
    /// - Parameter enabled: If true, includes original audio from video clips
    /// - Returns: Self for chaining
    func setEnableAudio(_ enabled: Bool) -> CompositionBuilder {
        self.enableAudio = enabled
        return self
    }
    
    /// Sets custom audio path.
    ///
    /// - Parameter path: Path to custom audio file
    /// - Returns: Self for chaining
    func setCustomAudioPath(_ path: String?) -> CompositionBuilder {
        self.customAudioPath = path
        return self
    }
    
    /// Sets volume for original video audio.
    ///
    /// - Parameter volume: Volume multiplier (0.0 to 1.0+)
    /// - Returns: Self for chaining
    func setOriginalAudioVolume(_ volume: Float?) -> CompositionBuilder {
        self.originalAudioVolume = volume ?? 1.0
        return self
    }
    
    /// Sets volume for custom audio.
    ///
    /// - Parameter volume: Volume multiplier (0.0 to 1.0+)
    /// - Returns: Self for chaining
    func setCustomAudioVolume(_ volume: Float?) -> CompositionBuilder {
        self.customAudioVolume = volume ?? 1.0
        return self
    }
    
    /// Builds the complete composition.
    ///
    /// - Returns: Tuple containing composition, video composition, render size, and audio mix
    /// - Throws: Error if composition creation fails
    func build() async throws -> (AVMutableComposition, AVMutableVideoComposition, CGSize, AVAudioMix?) {
        guard !videoClips.isEmpty else {
            throw NSError(
                domain: "CompositionBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Video clips cannot be empty"]
            )
        }
        
        print("🎬 Creating composition with \(videoClips.count) video clips")
        print("🔊 Audio enabled: \(enableAudio)")
        
        let composition = AVMutableComposition()
        
        // Build video sequence
        let videoBuilder = VideoSequenceBuilder(videoClips: videoClips)
            .setEnableAudio(enableAudio)
            .setOriginalAudioVolume(originalAudioVolume)
        
        // Check if we need to mix custom audio with original
        let needsAudioMixing = customAudioPath != nil &&
                               !(customAudioPath?.isEmpty ?? true) &&
                               originalAudioVolume > 0.0
        
        // Check sample rate compatibility if mixing audio
        var forceRemoveOriginalAudio = false
        if needsAudioMixing, let customPath = customAudioPath {
            let audioBuilder = AudioSequenceBuilder(
                audioPath: customPath,
                targetDuration: await videoBuilder.calculateTotalDuration()
            )
            let isCompatible = await audioBuilder.checkSampleRateCompatibility(videoClips: videoClips)
            forceRemoveOriginalAudio = !isCompatible
            
            if forceRemoveOriginalAudio {
                print("❌ Audio mixing DISABLED - sample rate mismatch detected")
                print("❌ Only custom audio will be used (original audio removed)")
            } else {
                print("✅ Audio mixing ENABLED (original: \(originalAudioVolume)x, custom: \(customAudioVolume)x)")
                print("✅ Sample rates are compatible - both audio tracks will be mixed")
            }
        }
        
        // Build video sequence (may force remove audio if incompatible)
        if forceRemoveOriginalAudio {
            _ = videoBuilder.setEnableAudio(false)
        }
        
        let videoResult = try await videoBuilder.build(in: composition)
        
        // Add custom audio track if provided
        var customAudioTrack: AVMutableCompositionTrack?
        if let customPath = customAudioPath, !customPath.isEmpty {
            print("🎵 Adding custom audio track: \(customPath)")
            let audioBuilder = AudioSequenceBuilder(
                audioPath: customPath,
                targetDuration: videoResult.totalDuration
            ).setVolume(customAudioVolume)
            
            customAudioTrack = try await audioBuilder.build(in: composition)
        }
        
        // Create audio mix with volume parameters
        var audioMix: AVAudioMix?
        if enableAudio && !forceRemoveOriginalAudio && (originalAudioVolume != 1.0 || customAudioVolume != 1.0) {
            audioMix = createAudioMix(
                originalTracks: videoResult.audioTracks,
                customTrack: customAudioTrack,
                originalVolume: originalAudioVolume,
                customVolume: customAudioVolume
            )
        }
        
        // Create video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: Int32(max(30, videoResult.frameRate))
        )
        videoComposition.renderSize = videoResult.renderSize
        
        // Create single instruction for the entire composition track
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: videoResult.totalDuration)
        instruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // Create layer instruction for the composition video track
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: videoResult.videoTrack
        )
        layerInstruction.setTransform(videoResult.transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        
        videoComposition.instructions = [instruction]
        
        print("✅ Composition created successfully with \(videoClips.count) clips")
        
        return (composition, videoComposition, videoResult.renderSize, audioMix)
    }
    
    /// Creates audio mix with volume parameters.
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
}
