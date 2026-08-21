import SwiftUI
import YoushuData
import YoushuDomain
import YoushuUI

@main
struct FinSightApp: App {
    private let dependencies = AppDependencies(
        repositories: .fileBacked(url: Self.storeURL),
        mediaBinaryRootURL: Self.mediaOriginalsRootURL,
        sourceAppVersionProvider: { AppVersionProvider.currentVersionString() }
    )

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
        }
    }

    private static var storeURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("Youshu", isDirectory: true)
            .appendingPathComponent("youshu-store.json")
    }

    private static var mediaOriginalsRootURL: URL {
        MediaStorageLocation.originalImagesRoot(nearDocumentStore: storeURL)
    }
}
