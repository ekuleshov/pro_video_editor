import AVFoundation
import Foundation

/// Adds audio tracks from a video asset to the composition.
///
/// Extracts the first audio track from the source asset and inserts it into
/// the composition. This preserves the original video's audio during export.
///
/// - Parameters:
///   - asset: Source video asset containing audio tracks.
///   - composition: Target composition to add audio to.
///   - timeRange: Time range to extract from the audio track.
///   - enableAudio: If false, audio is stripped (not added to composition).
///
/// - Note: Only the first audio track is used. Multiple audio tracks are not supported.
public func applyAudio(
    from asset: AVAsset,
    to composition: AVMutableComposition,
    timeRange: CMTimeRange,
    enableAudio: Bool
) async {
    guard enableAudio else {
        print("[\(Tags.render)] 🔇 Audio disabled - removing audio from export")
        return
    }

    do {
        let audioTracks: [AVAssetTrack]
        if #available(iOS 15.0, *) {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } else {
            audioTracks = asset.tracks(withMediaType: .audio)
        }

        if let audioTrack = audioTracks.first {
            if let audioCompositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try? audioCompositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                print("[\(Tags.render)] 🔊 Audio track added successfully")
            }
        } else {
            print("[\(Tags.render)] ℹ️ No audio track found in source video")
        }
    } catch {
        print("[\(Tags.render)] ⚠️ Failed to load audio tracks: \(error.localizedDescription)")
    }
}
