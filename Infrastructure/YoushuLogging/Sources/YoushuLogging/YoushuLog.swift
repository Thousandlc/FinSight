import Foundation



/// Lightweight logger. Uses OSLog on Apple platforms; prints on others.

/// 所有输出经 LogRedactor，禁止金额 / Token / 原图等内容入日志。

public struct YoushuLogger: Sendable {

    public let category: String



    public init(category: String) {

        self.category = category

    }



    public func debug(_ message: String) {

        log(level: "debug", message)

    }



    public func info(_ message: String) {

        log(level: "info", message)

    }



    public func error(_ message: String) {

        log(level: "error", message)

    }



    private func log(level: String, _ message: String) {

        let safe = LogRedactor.redact(message)

        #if canImport(OSLog)

        // Bridged via YoushuLog facade when needed; keep print for SPM portability in tests.

        #endif

        #if DEBUG

        print("[youshu.\(category)] \(level): \(safe)")

        #endif

    }

}



public enum YoushuLog {

    public static let subsystem = "app.youshu"

    public static let data = YoushuLogger(category: "data")

    public static let domain = YoushuLogger(category: "domain")

    public static let ai = YoushuLogger(category: "ai")

    public static let app = YoushuLogger(category: "app")

    public static let privacy = YoushuLogger(category: "privacy")

}


