import Foundation

protocol YoushuStorePersistenceIO: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

struct FoundationYoushuStorePersistenceIO: YoushuStorePersistenceIO {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }
}

enum SimulatedPersistenceFailure: Equatable {
    case read
    case write
}

/// Internal test seam for deterministic restore transaction failure injection.
final class SimulatedYoushuStorePersistenceIO: YoushuStorePersistenceIO, @unchecked Sendable {
    private let underlying = FoundationYoushuStorePersistenceIO()
    private let lock = NSLock()
    private var queuedFailures: [SimulatedPersistenceFailure] = []
    private(set) var readCallCount = 0
    private(set) var writeCallCount = 0

    func queueFailures(_ failures: [SimulatedPersistenceFailure]) {
        lock.lock()
        queuedFailures = failures
        lock.unlock()
    }

    func reset() {
        queueFailures([])
        lock.lock()
        readCallCount = 0
        writeCallCount = 0
        lock.unlock()
    }

    func queuedFailureCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return queuedFailures.count
    }

    func createDirectory(at url: URL) throws {
        try underlying.createDirectory(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        underlying.fileExists(at: url)
    }

    func read(from url: URL) throws -> Data {
        lock.lock()
        readCallCount += 1
        lock.unlock()
        if consumeFailure(.read) {
            throw DataError.persistenceFailed("simulated read failure")
        }
        return try underlying.read(from: url)
    }

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        writeCallCount += 1
        lock.unlock()
        if consumeFailure(.write) {
            throw DataError.persistenceFailed("simulated write failure")
        }
        try underlying.write(data, to: url)
    }

    private func consumeFailure(_ kind: SimulatedPersistenceFailure) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard queuedFailures.first == kind else { return false }
        queuedFailures.removeFirst()
        return true
    }
}
