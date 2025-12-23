import AVFoundation
import Foundation

/// Utility class for extracting media information from video and audio files.
///
/// Provides methods to extract duration, channel count, and sample rate
/// using AVFoundation APIs.
internal class MediaInfoExtractor {
    
    // MARK: - Duration Extraction
    
    /// Retrieves video duration from file.
    ///
    /// - Parameter videoPath: Absolute path to video file
    /// - Returns: Duration in microseconds, or 0 if not found
    static func getVideoDuration(_ videoPath: String) async -> Int64 {
        let url = URL(fileURLWithPath: videoPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Video file does not exist: \(videoPath)")
            return 0
        }
        
        let asset = AVURLAsset(url: url)
        
        do {
            let duration: CMTime
            if #available(macOS 13.0, *) {
                duration = try await asset.load(.duration)
            } else {
                duration = asset.duration
            }
            
            guard duration.seconds.isFinite else {
                return 0
            }
            
            return Int64(duration.seconds * 1_000_000)
        } catch {
            print("❌ Failed to get video duration for \(videoPath): \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Retrieves audio duration from file.
    ///
    /// - Parameter audioPath: Absolute path to audio file
    /// - Returns: Duration in microseconds, or 0 if not found
    static func getAudioDuration(_ audioPath: String) async -> Int64 {
        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Audio file does not exist: \(audioPath)")
            return 0
        }
        
        let asset = AVURLAsset(url: url)
        
        do {
            let duration: CMTime
            if #available(macOS 13.0, *) {
                duration = try await asset.load(.duration)
            } else {
                duration = asset.duration
            }
            
            guard duration.seconds.isFinite else {
                return 0
            }
            
            let durationUs = Int64(duration.seconds * 1_000_000)
            print("🔍 Audio duration: \(durationUs / 1000) ms")
            return durationUs
        } catch {
            print("❌ Failed to get audio duration: \(error.localizedDescription)")
            return 0
        }
    }
    
    // MARK: - Audio Channel Detection
    
    /// Detects the number of audio channels in a video file.
    ///
    /// - Parameter videoPath: Absolute path to video file
    /// - Returns: Number of channels (1=mono, 2=stereo, 6=5.1), or nil if not found
    static func getAudioChannelCount(_ videoPath: String) async -> Int? {
        let url = URL(fileURLWithPath: videoPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        let asset = AVURLAsset(url: url)
        
        do {
            let tracks: [AVAssetTrack]
            if #available(macOS 13.0, *) {
                tracks = try await asset.loadTracks(withMediaType: .audio)
            } else {
                tracks = asset.tracks(withMediaType: .audio)
            }
            
            guard let audioTrack = tracks.first else {
                return nil
            }
            
            let formatDescriptions: [Any]
            if #available(macOS 13.0, *) {
                formatDescriptions = try await audioTrack.load(.formatDescriptions)
            } else {
                formatDescriptions = audioTrack.formatDescriptions
            }
            
            for description in formatDescriptions {
                let formatDesc = description as! CMFormatDescription
                if let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                    let channelCount = Int(basicDesc.pointee.mChannelsPerFrame)
                    print("🔍 File \(videoPath): \(channelCount) audio channels")
                    return channelCount
                }
            }
            
            return nil
        } catch {
            print("❌ Failed to detect audio channels for \(videoPath): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Detects sample rate of an audio file.
    ///
    /// - Parameter audioPath: Absolute path to audio file
    /// - Returns: Sample rate in Hz (e.g., 48000), or 0 if not found
    static func getAudioSampleRate(_ audioPath: String) async -> Int {
        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }
        
        let asset = AVURLAsset(url: url)
        
        do {
            let tracks: [AVAssetTrack]
            if #available(macOS 13.0, *) {
                tracks = try await asset.loadTracks(withMediaType: .audio)
            } else {
                tracks = asset.tracks(withMediaType: .audio)
            }
            
            guard let audioTrack = tracks.first else {
                return 0
            }
            
            let formatDescriptions: [Any]
            if #available(macOS 13.0, *) {
                formatDescriptions = try await audioTrack.load(.formatDescriptions)
            } else {
                formatDescriptions = audioTrack.formatDescriptions
            }
            
            for description in formatDescriptions {
                let formatDesc = description as! CMFormatDescription
                if let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                    let sampleRate = Int(basicDesc.pointee.mSampleRate)
                    print("🔍 Audio sample rate: \(sampleRate) Hz")
                    return sampleRate
                }
            }
            
            return 0
        } catch {
            print("❌ Failed to detect audio sample rate: \(error.localizedDescription)")
            return 0
        }
    }
    
    // MARK: - Track Loading Helpers
    
    /// Loads video track from asset.
    static func loadVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        if #available(macOS 13.0, *) {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw NSError(
                    domain: "MediaInfoExtractor",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No video track found"]
                )
            }
            return track
        } else {
            guard let track = asset.tracks(withMediaType: .video).first else {
                throw NSError(
                    domain: "MediaInfoExtractor",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No video track found"]
                )
            }
            return track
        }
    }
    
    /// Loads audio track from asset.
    static func loadAudioTrack(from asset: AVAsset) async throws -> AVAssetTrack? {
        if #available(macOS 13.0, *) {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return tracks.first
        } else {
            return asset.tracks(withMediaType: .audio).first
        }
    }
}
