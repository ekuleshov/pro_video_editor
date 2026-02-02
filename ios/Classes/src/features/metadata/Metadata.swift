import AVFoundation
import Foundation

/// Service for extracting metadata from video files.
///
/// This class provides functionality to retrieve comprehensive metadata information
/// from video files using AVFoundation, including technical properties (dimensions,
/// duration, bitrate, rotation) and descriptive metadata (title, artist, album).
///
/// The extraction process is asynchronous and supports both modern async/await APIs
/// (iOS 15+) and legacy callback-based APIs for backwards compatibility.
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
    ///   - checkStreamingOptimization: Whether to check if the video is optimized for streaming
    /// - Returns: Dictionary containing all extracted metadata with string keys and typed values
    /// - Throws: Error if the file cannot be accessed or metadata extraction fails
    static func processVideo(inputPath: String, ext: String, checkStreamingOptimization: Bool = false) async throws -> [String: Any] {
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
        
        // Load duration using async API on iOS 15+ or fallback to synchronous API
        let duration: CMTime
        if #available(iOS 15.0, *) {
            duration = try await asset.load(.duration)
        } else {
            duration = asset.duration
        }
        let durationMs = CMTimeGetSeconds(duration) * 1000.0

        // MARK: - Audio Track Duration
        
        // Extract audio track duration if present
        var audioDurationMs: Double? = nil
        if #available(iOS 15.0, *) {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = audioTracks.first {
                let audioTimeRange = try await audioTrack.load(.timeRange)
                audioDurationMs = CMTimeGetSeconds(audioTimeRange.duration) * 1000.0
            }
        } else {
            // Fallback for iOS versions before 15.0
            if let audioTrack = asset.tracks(withMediaType: .audio).first {
                audioDurationMs = CMTimeGetSeconds(audioTrack.timeRange.duration) * 1000.0
            }
        }

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
        if #available(iOS 15.0, *) {
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
            // Fallback for iOS versions before 15.0
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

        if #available(iOS 15.0, *) {
            // Use async API to load metadata items
            let metadataItems = try await asset.load(.commonMetadata)
            for (resultKey, metadataKey) in textMetadataKeys {
                textMetadata[resultKey] = try await loadMetadataString(from: metadataItems, key: metadataKey)
            }
        } else {
            // Fallback for iOS versions before 15.0 using synchronous API
            let metadataItems = asset.commonMetadata
            for (resultKey, metadataKey) in textMetadataKeys {
                textMetadata[resultKey] = metadataItems.first(where: { $0.commonKey?.rawValue == metadataKey })?.stringValue ?? ""
            }
        }

        // MARK: - Creation Date
        
        // Extract creation date, first from metadata, then fallback to file system
        var dateStr = ""
        if #available(iOS 15.0, *) {
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
        var metadataDict: [String: Any] = [
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
        
        // Add audio duration if present
        if let audioDuration = audioDurationMs {
            metadataDict["audioDuration"] = audioDuration
        }
        
        // Check if video is optimized for streaming (moov before mdat)
        // Only perform this check if explicitly requested (performance optimization)
        if checkStreamingOptimization {
            if #available(iOS 13.4, *) {
                if let isOptimized = Self.checkStreamingOptimization(url: tempFileURL) {
                    metadataDict["isOptimizedForStreaming"] = isOptimized
                }
            }
        }
        
        return metadataDict
    }

    // MARK: - Audio Track Check
    
    /// Asynchronously checks if a video file has an audio track.
    ///
    /// This method inspects the video file to determine if it contains at least
    /// one audio track. This is useful to check before attempting audio extraction
    /// operations to avoid errors.
    ///
    /// - Parameter inputPath: The absolute file path to the video file
    /// - Returns: `true` if the video has at least one audio track, `false` otherwise
    /// - Throws: Error if the file cannot be accessed or check fails
    static func checkAudioTrack(inputPath: String) async throws -> Bool {
        let tempFileURL = URL(fileURLWithPath: inputPath)
        let asset = AVURLAsset(url: tempFileURL)
        
        // Check for audio tracks
        if #available(iOS 15.0, *) {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return !audioTracks.isEmpty
        } else {
            // Fallback for iOS versions before 15.0
            let audioTracks = asset.tracks(withMediaType: .audio)
            return !audioTracks.isEmpty
        }
    }

    // MARK: - Helper Methods
    
    /// Asynchronously loads a string value from metadata items by key.
    ///
    /// - Parameters:
    ///   - metadata: Array of AVMetadataItem to search
    ///   - key: The common key to search for (e.g., "title", "artist")
    /// - Returns: The string value if found, empty string otherwise
    @available(iOS 15.0, *)
    private static func loadMetadataString(from metadata: [AVMetadataItem], key: String)
        async throws -> String
    {
        if let item = metadata.first(where: { $0.commonKey?.rawValue == key }) {
            return try await item.load(.stringValue) ?? ""
        }
        return ""
    }
    
    // MARK: - Streaming Optimization Check
    
    /// Checks if the video file is optimized for progressive streaming.
    ///
    /// For MP4/MOV files, this checks if the moov atom appears before the mdat atom.
    /// When moov comes first, browsers can start playback before downloading the
    /// entire file (progressive streaming / fast start).
    ///
    /// - Parameter url: URL to the video file
    /// - Returns: true if optimized for streaming (moov before mdat), false if not,
    ///            nil if the format doesn't support this check or an error occurred
    @available(iOS 13.4, *)
    private static func checkStreamingOptimization(url: URL) -> Bool? {
        // Only check MP4/MOV/M4V files
        let ext = url.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v", "m4a"].contains(ext) else {
            return nil
        }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        
        defer {
            try? fileHandle.close()
        }
        
        var moovPosition: UInt64? = nil
        var mdatPosition: UInt64? = nil
        var position: UInt64 = 0
        
        while true {
            // Read atom header (4 bytes size + 4 bytes type)
            guard let headerData = try? fileHandle.read(upToCount: 8),
                  headerData.count == 8 else {
                break
            }
            
            // Parse atom size (big-endian)
            let atomSize = UInt64(headerData[0]) << 24 |
                          UInt64(headerData[1]) << 16 |
                          UInt64(headerData[2]) << 8 |
                          UInt64(headerData[3])
            
            // Parse atom type
            let atomType = String(data: headerData[4..<8], encoding: .ascii) ?? ""
            
            // Track positions of moov and mdat atoms
            switch atomType {
            case "moov":
                moovPosition = position
            case "mdat":
                mdatPosition = position
            default:
                break
            }
            
            // If we found both, we can determine the result
            if let moov = moovPosition, let mdat = mdatPosition {
                return moov < mdat
            }
            
            // Handle extended size (atomSize == 1 means 64-bit size follows)
            var actualSize: UInt64
            if atomSize == 1 {
                // Read 64-bit size
                guard let extData = try? fileHandle.read(upToCount: 8),
                      extData.count == 8 else {
                    break
                }
                let byte0: UInt64 = UInt64(extData[0]) << 56
                let byte1: UInt64 = UInt64(extData[1]) << 48
                let byte2: UInt64 = UInt64(extData[2]) << 40
                let byte3: UInt64 = UInt64(extData[3]) << 32
                let byte4: UInt64 = UInt64(extData[4]) << 24
                let byte5: UInt64 = UInt64(extData[5]) << 16
                let byte6: UInt64 = UInt64(extData[6]) << 8
                let byte7: UInt64 = UInt64(extData[7])
                actualSize = byte0 | byte1 | byte2 | byte3 | byte4 | byte5 | byte6 | byte7
            } else if atomSize == 0 {
                // Atom extends to end of file
                break
            } else {
                actualSize = atomSize
            }
            
            // Skip to next atom
            _ = actualSize - 8 - (atomSize == 1 ? 8 : 0)
            position += actualSize
            
            do {
                try fileHandle.seek(toOffset: position)
            } catch {
                break
            }
        }
        
        // If we only found one of them, determine based on what we found
        if moovPosition != nil && mdatPosition == nil {
            return true  // moov found, no mdat yet
        } else if moovPosition == nil && mdatPosition != nil {
            return false // mdat found first, no moov
        }
        
        return nil // Neither found or couldn't determine
    }
}
