import Foundation

/// Canonical filesystem layout for app-private media binaries (separate from JSON document store).
public enum MediaStorageLocation {
    /// Returns the directory for user-retained original image binaries.
    /// Located alongside the live JSON store under Application Support/Youshu/.
    public static func originalImagesRoot(nearDocumentStore storeFileURL: URL) -> URL {
        storeFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("media-originals", isDirectory: true)
    }
}
