import AVFoundation

/// Adjusts video playback speed by time-scaling the composition.
///
/// Changes the playback speed by scaling the time range of all tracks in the composition.
/// This affects both video and audio tracks equally.
///
/// - Parameters:
///   - composition: Composition to modify.
///   - speed: Playback speed multiplier.
///            - 0.5 = half speed (slow motion)
///            - 1.0 = normal speed (no change)
///            - 2.0 = double speed (fast forward)
///            - nil or 1.0 = no change
///
/// - Note: Speed must be positive. Values ≤0 or exactly 1.0 are ignored.
public func applyPlaybackSpeed(
    composition: AVMutableComposition,
    speed: Float?
) {
    guard let speed = speed, speed > 0, speed != 1 else { return }

    let speedType = speed < 1 ? "slow motion" : "fast forward"
    print("[\(Tags.render)] ⚡ Applying playback speed: \(String(format: "%.2f", speed))x (\(speedType))")

    let tracks = composition.tracks
    for track in tracks {
        let range = CMTimeRange(start: .zero, duration: track.timeRange.duration)
        let scaledDuration = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / Double(speed))
        track.scaleTimeRange(range, toDuration: scaledDuration)
    }
}
