import AVFoundation
import Foundation

/// Service for extracting metadata from video files.
///
/// This class provides functionality to retrieve comprehensive metadata information
/// from video files using AVFoundation, including technical properties (dimensions,
/// duration, bitrate, rotation) and descriptive metadata (title, artist, album).
///
/// The extraction process is asynchronous and supports both modern async/await APIs
/// (macOS 13+) and legacy callback-based APIs for backwards compatibility.
class VideoMetadata {

    /// Asynchronously extracts metadata from a video file.
    ///
    /// This method processes the video file at the specified path and extracts all
    /// available metadata. The operation is organized into categories:
    /// - File properties (file size, creation date)
    /// - Video properties (dimensions, rotation, duration, bitrate)
    /// - Descriptive metadata (title, artist, author, album information)
    ///
    /// - Parameters:
    ///   - inputPath: The absolute file path to the video file
    ///   - ext: The file extension (e.g., "mp4", "mov")
    /// - Returns: Dictionary containing all extracted metadata with string keys and typed values
    /// - Throws: Error if the file cannot be accessed or metadata extraction fails
    static func processVideo(inputPath: String, ext: String) async throws -> [String: Any] {
       let tempFileURL = URL(fileURLWithPath: inputPath)
       let asset = AVURLAsset(url: tempFileURL)

        // MARK: - File Properties
        
        // Extract file size from file system attributes
        let fileSize: Int64
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: tempFileURL.path)
            fileSize = attr[.size] as? Int64 ?? 0
        } catch {
            return ["error": "Failed to get file size: \(error.localizedDescription)"]
        }

        // MARK: - Duration Extraction
        
        // Load duration using async API on macOS 13+ or fallback to synchronous API
        let duration: CMTime
        if #available(macOS 13.0, *) {
            duration = try await asset.load(.duration)
        } else {
            duration = asset.duration
        }
        let durationMs = CMTimeGetSeconds(duration) * 1000.0

        // MARK: - Video Track Properties
        
        // Initialize numeric properties with default values
        var numericMetadata: [String: Int] = [
            "width": 0,
            "height": 0,
            "rotation": 0,
            "bitrate": 0
        ]

        // Calculate bitrate from file size and duration
        // Bitrate (bps) = (file size in bits) / (duration in seconds)
        if durationMs > 0 {
            let fileSizeBits = fileSize * 8
            numericMetadata["bitrate"] = Int(Double(fileSizeBits) * 1000 / durationMs)
        }

        // Extract video dimensions and rotation from the first video track
        // The dimensions must account for the preferred transform (rotation/flip)
        if #available(macOS 13.0, *) {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let track = videoTracks.first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                
                // Apply transform to get actual display dimensions
                let transformedSize = size.applying(transform)
                numericMetadata["width"] = Int(abs(transformedSize.width))
                numericMetadata["height"] = Int(abs(transformedSize.height))

                // Calculate rotation angle from transform matrix
                // atan2(b, a) gives the rotation angle in radians
                let angle = atan2(transform.b, transform.a)
                numericMetadata["rotation"] = (Int(round(angle * 180 / .pi)) + 360) % 360
            }
        } else {
            // Fallback for macOS versions before 13.0
            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                numericMetadata["width"] = Int(abs(size.width))
                numericMetadata["height"] = Int(abs(size.height))

                let angle = atan2(track.preferredTransform.b, track.preferredTransform.a)
                numericMetadata["rotation"] = (Int(round(angle * 180 / .pi)) + 360) % 360
            }
        }

        // MARK: - Descriptive Metadata
        
        // Extract text-based metadata (title, artist, album information)
        // These values are stored in the video file's common metadata
        // Using a map-based approach for cleaner, more maintainable code
        let textMetadataKeys = [
            "title": "title",
            "artist": "artist",
            "author": "author",
            "album": "albumName",
            "albumArtist": "albumArtist"
        ]
        
        var textMetadata: [String: String] = [:]

        if #available(macOS 13.0, *) {
            // Use async API to load metadata items
            let metadataItems = try await asset.load(.commonMetadata)
            for (resultKey, metadataKey) in textMetadataKeys {
                textMetadata[resultKey] = try await loadMetadataString(from: metadataItems, key: metadataKey)
            }
        } else {
            // Fallback for macOS versions before 13.0 using synchronous API
            let metadataItems = asset.commonMetadata
            for (resultKey, metadataKey) in textMetadataKeys {
                textMetadata[resultKey] = metadataItems.first(where: { $0.commonKey?.rawValue == metadataKey })?.stringValue ?? ""
            }
        }

        // MARK: - Creation Date
        
        // Extract creation date, first from metadata, then fallback to file system
        var dateStr = ""
        if #available(macOS 13.0, *) {
            // Try to load creation date from video metadata
            if let creationItem = try await asset.load(.creationDate) {
                if let creationDate = try? await creationItem.load(.dateValue) {
                    dateStr = ISO8601DateFormatter().string(from: creationDate)
                }
            }
        }
        // Fallback to file system creation date if metadata date is not available
        if dateStr.isEmpty {
            if let attr = try? FileManager.default.attributesOfItem(atPath: tempFileURL.path),
                let fileCreationDate = attr[.creationDate] as? Date
            {
                dateStr = ISO8601DateFormatter().string(from: fileCreationDate)
            }
        }

        // MARK: - Return Metadata Dictionary
        
        // Compile all extracted metadata into a dictionary for Flutter
        return [
            "fileSize": fileSize,                                   // File size in bytes
            "duration": durationMs,                                 // Duration in milliseconds
            "width": numericMetadata["width"] ?? 0,                 // Video width in pixels
            "height": numericMetadata["height"] ?? 0,               // Video height in pixels
            "rotation": numericMetadata["rotation"] ?? 0,           // Rotation in degrees (0, 90, 180, 270)
            "bitrate": numericMetadata["bitrate"] ?? 0,             // Bitrate in bits per second
            "title": textMetadata["title"] ?? "",                   // Video title metadata
            "artist": textMetadata["artist"] ?? "",                 // Artist metadata
            "author": textMetadata["author"] ?? "",                 // Author metadata
            "album": textMetadata["album"] ?? "",                   // Album metadata
            "albumArtist": textMetadata["albumArtist"] ?? "",       // Album artist metadata
            "date": dateStr,                                        // Creation date in ISO8601 format
        ]
    }

    // MARK: - Helper Methods
    
    /// Asynchronously loads a string value from metadata items by key.
    ///
    /// - Parameters:
    ///   - metadata: Array of AVMetadataItem to search
    ///   - key: The common key to search for (e.g., "title", "artist")
    /// - Returns: The string value if found, empty string otherwise
    @available(macOS 13.0, *)
    private static func loadMetadataString(from metadata: [AVMetadataItem], key: String)
        async throws -> String
    {
        if let item = metadata.first(where: { $0.commonKey?.rawValue == key }) {
            return try await item.load(.stringValue) ?? ""
        }
        return ""
    }
}
