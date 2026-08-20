import Foundation

/// Resolves the application version string for backup provenance metadata.
public enum AppVersionProvider {
    public static func currentVersionString(bundle: Bundle = .main) -> String? {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, buildNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
        case (false, false):
            return "\(shortVersion!) (\(buildNumber!))"
        case (false, true):
            return shortVersion
        case (true, false):
            return buildNumber
        default:
            return nil
        }
    }
}
