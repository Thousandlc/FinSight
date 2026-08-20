import SwiftUI
import UniformTypeIdentifiers

public enum FinSightBackupDocumentType {
    /// FinSight encrypted backup file type for system Files integration.
    public static let identifier = "app.finsight.backup"

    public static var utType: UTType {
        UTType(exportedAs: identifier, conformingTo: .data)
    }
}

/// Encrypted backup bytes handed to the system Files exporter.
public struct FinSightBackupExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [FinSightBackupDocumentType.utType] }

    public let encryptedData: Data

    public init(encryptedData: Data) {
        self.encryptedData = encryptedData
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        encryptedData = data
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: encryptedData)
    }
}
