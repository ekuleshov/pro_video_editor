import AVFoundation

/// Calculates the time range for trimming a video asset.
///
/// Creates a CMTimeRange that defines which portion of the video to use.
/// Times are specified in microseconds for precision. If no trim is specified,
/// the full video duration is used.
///
/// - Parameters:
///   - asset: Video asset to trim.
///   - startUs: Start time in microseconds. nil = start from beginning.
///   - endUs: End time in microseconds. nil = use full duration.
///
/// - Returns: CMTimeRange defining the trimmed portion of the video.
///
/// - Note: Times are converted from microseconds to CMTime for AVFoundation.
public func applyTrim(
    asset: AVAsset,
    startUs: Int64?,
    endUs: Int64?
) async -> CMTimeRange {
    // Load duration
    let duration: CMTime
    if #available(iOS 15.0, *) {
        do {
            duration = try await asset.load(.duration)
        } catch {
            return CMTimeRange(start: .zero, duration: .positiveInfinity)
        }
    } else {
        duration = asset.duration
    }

    // Prepare start and end CMTime
    let start = startUs != nil
        ? CMTime(value: startUs!, timescale: 1_000_000)
        : .zero

    let end = endUs != nil
        ? CMTime(value: endUs!, timescale: 1_000_000)
        : duration

    // Logging in seconds for easier debugging
    let startSec = String(format: "%.2f", start.seconds)
    let endSec = String(format: "%.2f", end.seconds)
    let durationSec = String(format: "%.2f", (end - start).seconds)
    print("[\(Tags.render)] ✂️ Applying trim: start=\(startSec)s, end=\(endSec)s, duration=\(durationSec)s")

    return CMTimeRange(start: start, end: end)
}
