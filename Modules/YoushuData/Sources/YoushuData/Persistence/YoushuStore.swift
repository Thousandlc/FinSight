import Foundation
import YoushuDomain
import YoushuLogging

public enum DataError: Error, Equatable, Sendable {
    case notFound(entity: String, id: UUID)
    case invalidRelation(String)
    case persistenceFailed(String)
    case schemaUnsupported(found: Int, supported: Int)
}

/// Local JSON document store. Production iOS will keep this contract and may swap
/// the backend to SwiftData without changing Domain ports.
public actor YoushuStore {
    private var snapshot: YoushuSnapshot
    private let fileURL: URL?
    private let persistenceIO: YoushuStorePersistenceIO
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, snapshot: YoushuSnapshot = .empty) {
        self.init(
            fileURL: fileURL,
            snapshot: snapshot,
            persistenceIO: FoundationYoushuStorePersistenceIO()
        )
    }

    init(
        fileURL: URL? = nil,
        snapshot: YoushuSnapshot = .empty,
        persistenceIO: YoushuStorePersistenceIO
    ) {
        self.fileURL = fileURL
        self.snapshot = snapshot
        self.persistenceIO = persistenceIO
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func load(from fileURL: URL) async throws -> YoushuStore {
        let store = YoushuStore(fileURL: fileURL)
        try await store.reloadFromDisk()
        return store
    }

    public func currentSnapshot() -> YoushuSnapshot {
        snapshot
    }

    public func replaceSnapshot(_ snapshot: YoushuSnapshot) throws {
        guard snapshot.schemaVersion <= YoushuSnapshot.currentSchemaVersion else {
            throw DataError.schemaUnsupported(
                found: snapshot.schemaVersion,
                supported: YoushuSnapshot.currentSchemaVersion
            )
        }
        self.snapshot = snapshot
        try persistLocked()
    }

    /// Atomically replaces the persisted root with a validated restore candidate.
    ///
    /// Ordering: retain previous snapshot → write candidate → re-read/verify → publish in memory.
    /// On post-write verification failure, rolls back to the previous persisted snapshot.
    public func replaceSnapshotForRestore(_ candidate: YoushuSnapshot) throws {
        guard candidate.schemaVersion == YoushuSnapshot.currentSchemaVersion else {
            throw BackupRestoreError.commitPersistenceFailure
        }

        guard let fileURL else {
            snapshot = candidate
            return
        }

        let previousSnapshot = snapshot
        let previousData = try encodeSnapshotData(previousSnapshot)
        let candidateData = try encodeSnapshotData(candidate)

        do {
            try persistenceIO.createDirectory(at: fileURL.deletingLastPathComponent())
            try persistenceIO.write(candidateData, to: fileURL)
        } catch {
            throw BackupRestoreError.commitPersistenceFailure
        }

        do {
            let persistedCandidate = try readSnapshotFromDisk(at: fileURL)
            guard try snapshotsEqual(persistedCandidate, candidate) else {
                throw BackupRestoreError.postWriteVerificationFailure
            }
        } catch let error as BackupRestoreError {
            try rollbackRestore(
                previousData: previousData,
                previousSnapshot: previousSnapshot,
                fileURL: fileURL,
                causedBy: error
            )
        } catch {
            try rollbackRestore(
                previousData: previousData,
                previousSnapshot: previousSnapshot,
                fileURL: fileURL,
                causedBy: .postWriteVerificationFailure
            )
        }

        snapshot = candidate
    }

    // MARK: - User

    public func upsertUser(_ user: User) throws {
        upsert(&snapshot.users, user)
        try persistLocked()
    }

    public func fetchUser(id: UUID) -> User? {
        snapshot.users.first { $0.id == id }
    }

    public func fetchAllUsers() -> [User] {
        snapshot.users
    }

    public func deleteUser(id: UUID) throws {
        snapshot.users.removeAll { $0.id == id }
        snapshot.accounts.removeAll { $0.userId == id }
        snapshot.transactions.removeAll { $0.userId == id }
        snapshot.assets.removeAll { $0.userId == id }
        let debtIds = Set(snapshot.debts.filter { $0.userId == id }.map(\.id))
        snapshot.debts.removeAll { $0.userId == id }
        snapshot.debtEvents.removeAll { debtIds.contains($0.debtId) || $0.userId == id }
        snapshot.repaymentPlans.removeAll { debtIds.contains($0.debtId) || $0.userId == id }
        snapshot.budgets.removeAll { $0.userId == id }
        snapshot.goals.removeAll { $0.userId == id }
        snapshot.subscriptions.removeAll { $0.userId == id }
        snapshot.insights.removeAll { $0.userId == id }
        snapshot.pendingDebtLinks.removeAll { $0.userId == id }
        snapshot.suspectedDebts.removeAll { $0.userId == id }
        snapshot.aiDataConsents.removeAll { $0.userId == id }
        snapshot.aiRecognitionRecords.removeAll { $0.userId == id }
        snapshot.mediaArtifacts.removeAll { $0.userId == id }
        snapshot.confirmedImportProvenances.removeAll { $0.userId == id }
        try persistLocked()
    }

    // MARK: - Account

    public func upsertAccount(_ account: Account) throws {
        try requireUser(account.userId)
        upsert(&snapshot.accounts, account)
        try persistLocked()
    }

    public func fetchAccount(id: UUID) -> Account? {
        snapshot.accounts.first { $0.id == id }
    }

    public func fetchAccounts(userId: UUID) -> [Account] {
        snapshot.accounts.filter { $0.userId == userId }
    }

    public func deleteAccount(id: UUID) throws {
        if snapshot.transactions.contains(where: { $0.accountId == id }) {
            throw DataError.invalidRelation("Cannot delete account with existing transactions")
        }
        snapshot.accounts.removeAll { $0.id == id }
        try persistLocked()
    }

    // MARK: - Transaction

    public func upsertTransaction(_ transaction: Transaction) throws {
        try requireUser(transaction.userId)
        guard let account = fetchAccount(id: transaction.accountId) else {
            throw DataError.invalidRelation("Account \(transaction.accountId) does not exist")
        }
        guard account.userId == transaction.userId else {
            throw DataError.invalidRelation("Transaction user does not own account")
        }
        if let debtId = transaction.relatedDebtId {
            guard let debt = fetchDebt(id: debtId), debt.userId == transaction.userId else {
                throw DataError.invalidRelation("relatedDebt must belong to the same user")
            }
        }
        upsert(&snapshot.transactions, transaction)
        try persistLocked()
    }

    public func fetchTransaction(id: UUID) -> Transaction? {
        snapshot.transactions.first { $0.id == id }
    }

    public func fetchTransactions(userId: UUID) -> [Transaction] {
        snapshot.transactions.filter { $0.userId == userId }
    }

    public func fetchTransactions(accountId: UUID) -> [Transaction] {
        snapshot.transactions.filter { $0.accountId == accountId }
    }

    public func fetchTransactions(relatedDebtId: UUID) -> [Transaction] {
        snapshot.transactions.filter { $0.relatedDebtId == relatedDebtId }
    }

    public func deleteTransaction(id: UUID) throws {
        snapshot.transactions.removeAll { $0.id == id }
        removeConfirmedImportEntityReference(.transaction(id))
        try persistLocked()
    }

    // MARK: - Debt

    public func upsertDebt(_ debt: Debt) throws {
        try requireUser(debt.userId)
        var value = debt
        value.profileCompleteness = DebtProfileCompleteness.score(for: value)
        upsert(&snapshot.debts, value)
        try persistLocked()
    }

    public func fetchDebt(id: UUID) -> Debt? {
        snapshot.debts.first { $0.id == id }
    }

    public func fetchDebts(userId: UUID) -> [Debt] {
        snapshot.debts.filter { $0.userId == userId }
    }

    public func deleteDebt(id: UUID) throws {
        snapshot.debts.removeAll { $0.id == id }
        snapshot.debtEvents.removeAll { $0.debtId == id }
        snapshot.repaymentPlans.removeAll { $0.debtId == id }
        // Keep transactions but detach debt link for auditability of facts.
        snapshot.transactions = snapshot.transactions.map { tx in
            guard tx.relatedDebtId == id else { return tx }
            var copy = tx
            copy.relatedDebtId = nil
            copy.updatedAt = Date()
            return copy
        }
        removeConfirmedImportEntityReference(.debt(id))
        try persistLocked()
    }

    // MARK: - DebtEvent

    public func upsertDebtEvent(_ event: DebtEvent) throws {
        try requireUser(event.userId)
        guard let debt = fetchDebt(id: event.debtId), debt.userId == event.userId else {
            throw DataError.invalidRelation("DebtEvent must reference a valid debt for the user")
        }
        if let txId = event.relatedTransactionId {
            guard let tx = fetchTransaction(id: txId), tx.userId == event.userId else {
                throw DataError.invalidRelation("DebtEvent.relatedTransactionId invalid")
            }
        }
        upsert(&snapshot.debtEvents, event)
        try persistLocked()
    }

    public func fetchDebtEvent(id: UUID) -> DebtEvent? {
        snapshot.debtEvents.first { $0.id == id }
    }

    public func fetchDebtEvents(debtId: UUID) -> [DebtEvent] {
        snapshot.debtEvents.filter { $0.debtId == debtId }
    }

    public func deleteDebtEvent(id: UUID) throws {
        snapshot.debtEvents.removeAll { $0.id == id }
        try persistLocked()
    }

    // MARK: - RepaymentPlan

    public func upsertRepaymentPlan(_ plan: RepaymentPlan) throws {
        try requireUser(plan.userId)
        guard let debt = fetchDebt(id: plan.debtId), debt.userId == plan.userId else {
            throw DataError.invalidRelation("RepaymentPlan must reference a valid debt")
        }
        upsert(&snapshot.repaymentPlans, plan)
        try persistLocked()
    }

    public func fetchRepaymentPlan(id: UUID) -> RepaymentPlan? {
        snapshot.repaymentPlans.first { $0.id == id }
    }

    public func fetchRepaymentPlans(debtId: UUID) -> [RepaymentPlan] {
        snapshot.repaymentPlans.filter { $0.debtId == debtId }
    }

    public func fetchRepaymentPlans(userId: UUID) -> [RepaymentPlan] {
        snapshot.repaymentPlans.filter { $0.userId == userId }
    }

    public func deleteRepaymentPlan(id: UUID) throws {
        snapshot.repaymentPlans.removeAll { $0.id == id }
        try persistLocked()
    }

    // MARK: - Other aggregates

    public func upsertAsset(_ asset: Asset) throws {
        try requireUser(asset.userId)
        upsert(&snapshot.assets, asset)
        try persistLocked()
    }

    public func fetchAssets(userId: UUID) -> [Asset] {
        snapshot.assets.filter { $0.userId == userId }
    }

    public func deleteAsset(id: UUID) throws {
        snapshot.assets.removeAll { $0.id == id }
        try persistLocked()
    }

    public func upsertBudget(_ budget: Budget) throws {
        try requireUser(budget.userId)
        upsert(&snapshot.budgets, budget)
        try persistLocked()
    }

    public func fetchBudgets(userId: UUID) -> [Budget] {
        snapshot.budgets.filter { $0.userId == userId }
    }

    public func deleteBudget(id: UUID) throws {
        snapshot.budgets.removeAll { $0.id == id }
        try persistLocked()
    }

    public func upsertGoal(_ goal: Goal) throws {
        try requireUser(goal.userId)
        upsert(&snapshot.goals, goal)
        try persistLocked()
    }

    public func fetchGoals(userId: UUID) -> [Goal] {
        snapshot.goals.filter { $0.userId == userId }
    }

    public func deleteGoal(id: UUID) throws {
        snapshot.goals.removeAll { $0.id == id }
        try persistLocked()
    }

    public func upsertSubscription(_ subscription: Subscription) throws {
        try requireUser(subscription.userId)
        upsert(&snapshot.subscriptions, subscription)
        try persistLocked()
    }

    public func fetchSubscriptions(userId: UUID) -> [Subscription] {
        snapshot.subscriptions.filter { $0.userId == userId }
    }

    public func deleteSubscription(id: UUID) throws {
        snapshot.subscriptions.removeAll { $0.id == id }
        try persistLocked()
    }

    public func upsertInsight(_ insight: FinancialInsight) throws {
        try requireUser(insight.userId)
        upsert(&snapshot.insights, insight)
        try persistLocked()
    }

    public func fetchInsights(userId: UUID) -> [FinancialInsight] {
        snapshot.insights.filter { $0.userId == userId }
    }

    public func deleteInsight(id: UUID) throws {
        snapshot.insights.removeAll { $0.id == id }
        try persistLocked()
    }

    // MARK: - PendingDebtLink

    public func upsertPendingDebtLink(_ link: PendingDebtLink) throws {
        try requireUser(link.userId)
        upsert(&snapshot.pendingDebtLinks, link)
        try persistLocked()
    }

    public func fetchPendingDebtLink(id: UUID) -> PendingDebtLink? {
        snapshot.pendingDebtLinks.first { $0.id == id }
    }

    public func fetchPendingDebtLinks(userId: UUID, pendingOnly: Bool) -> [PendingDebtLink] {
        snapshot.pendingDebtLinks.filter {
            $0.userId == userId && (!pendingOnly || $0.status == .pending)
        }
    }

    public func deletePendingDebtLink(id: UUID) throws {
        snapshot.pendingDebtLinks.removeAll { $0.id == id }
        try persistLocked()
    }

    // MARK: - SuspectedDebt

    public func upsertSuspectedDebt(_ suspected: SuspectedDebt) throws {
        try requireUser(suspected.userId)
        upsert(&snapshot.suspectedDebts, suspected)
        try persistLocked()
    }

    public func fetchSuspectedDebt(id: UUID) -> SuspectedDebt? {
        snapshot.suspectedDebts.first { $0.id == id }
    }

    public func fetchSuspectedDebts(userId: UUID, pendingOnly: Bool) -> [SuspectedDebt] {
        snapshot.suspectedDebts.filter {
            $0.userId == userId && (!pendingOnly || $0.status == .pending)
        }
    }

    public func deleteSuspectedDebt(id: UUID) throws {
        snapshot.suspectedDebts.removeAll { $0.id == id }
        try persistLocked()
    }

    // MARK: - AIDataConsent

    public func upsertAIDataConsent(_ consent: AIDataConsent) throws {
        try requireUser(consent.userId)
        if let idx = snapshot.aiDataConsents.firstIndex(where: { $0.userId == consent.userId }) {
            snapshot.aiDataConsents[idx] = consent
        } else {
            snapshot.aiDataConsents.append(consent)
        }
        try persistLocked()
    }

    public func fetchAIDataConsent(userId: UUID) -> AIDataConsent? {
        snapshot.aiDataConsents.first { $0.userId == userId }
    }

    public func deleteAIDataConsent(userId: UUID) throws {
        snapshot.aiDataConsents.removeAll { $0.userId == userId }
        try persistLocked()
    }

    // MARK: - AIRecognitionRecord

    public func upsertAIRecognitionRecord(_ record: AIRecognitionRecord) throws {
        try requireUser(record.userId)
        upsert(&snapshot.aiRecognitionRecords, record)
        try persistLocked()
    }

    public func fetchAIRecognitionRecord(id: UUID) -> AIRecognitionRecord? {
        snapshot.aiRecognitionRecords.first { $0.id == id }
    }

    public func fetchAIRecognitionRecords(userId: UUID) -> [AIRecognitionRecord] {
        snapshot.aiRecognitionRecords.filter { $0.userId == userId }
    }

    public func deleteAIRecognitionRecord(id: UUID) throws {
        snapshot.aiRecognitionRecords.removeAll { $0.id == id }
        try persistLocked()
    }

    public func deleteAIRecognitionRecords(userId: UUID) throws {
        snapshot.aiRecognitionRecords.removeAll { $0.userId == userId }
        try persistLocked()
    }

    // MARK: - MediaArtifact

    public func upsertMediaArtifact(_ artifact: MediaArtifact) throws {
        try requireUser(artifact.userId)
        if let idx = snapshot.mediaArtifacts.firstIndex(where: { $0.id == artifact.id }) {
            snapshot.mediaArtifacts[idx] = artifact
        } else {
            snapshot.mediaArtifacts.append(artifact)
        }
        try persistLocked()
    }

    public func fetchMediaArtifact(id: String) -> MediaArtifact? {
        snapshot.mediaArtifacts.first { $0.id == id }
    }

    public func fetchMediaArtifacts(userId: UUID) -> [MediaArtifact] {
        snapshot.mediaArtifacts.filter { $0.userId == userId }
    }

    public func deleteMediaArtifact(id: String) throws {
        snapshot.mediaArtifacts.removeAll { $0.id == id }
        try persistLocked()
    }

    public func deleteMediaArtifacts(userId: UUID) throws {
        snapshot.mediaArtifacts.removeAll { $0.userId == userId }
        try persistLocked()
    }

    // MARK: - ConfirmedImportProvenance

    public func upsertConfirmedImportProvenance(_ provenance: ConfirmedImportProvenance) throws -> ConfirmedImportProvenance {
        try requireUser(provenance.userId)
        let matches = snapshot.confirmedImportProvenances.enumerated().filter {
            $0.element.userId == provenance.userId
                && $0.element.capability == provenance.capability
                && $0.element.operationFingerprint == provenance.operationFingerprint
        }

        if matches.isEmpty {
            snapshot.confirmedImportProvenances.append(provenance)
            try persistLocked()
            return provenance
        }

        let existing = matches[0].element
        guard existing.capability == provenance.capability,
              existing.sourceFingerprints == provenance.sourceFingerprints,
              existing.operationFingerprint == provenance.operationFingerprint else {
            throw DataError.invalidRelation("Confirmed import provenance integrity mismatch for logical key")
        }

        var mergedReferences = existing.confirmedEntityReferences
        for reference in provenance.confirmedEntityReferences where !mergedReferences.contains(reference) {
            mergedReferences.append(reference)
        }
        let merged = try ConfirmedImportProvenance(
            id: existing.id,
            userId: existing.userId,
            capability: existing.capability,
            sourceFingerprints: existing.sourceFingerprints,
            confirmedEntityReferences: mergedReferences,
            confirmedAt: min(existing.confirmedAt, provenance.confirmedAt)
        )

        if matches.count > 1 {
            let duplicateIndices = matches.dropFirst().map(\.offset).sorted(by: >)
            for index in duplicateIndices {
                snapshot.confirmedImportProvenances.remove(at: index)
            }
        }
        upsert(&snapshot.confirmedImportProvenances, merged)
        try persistLocked()
        return merged
    }

    public func fetchConfirmedImportProvenance(id: UUID) -> ConfirmedImportProvenance? {
        snapshot.confirmedImportProvenances.first { $0.id == id }
    }

    public func fetchConfirmedImportProvenance(
        userId: UUID,
        capability: ConfirmedImportCapability,
        operationFingerprint: ImportOperationFingerprint
    ) -> ConfirmedImportProvenance? {
        snapshot.confirmedImportProvenances.first {
            $0.userId == userId
                && $0.capability == capability
                && $0.operationFingerprint == operationFingerprint
        }
    }

    public func fetchConfirmedImportProvenances(userId: UUID) -> [ConfirmedImportProvenance] {
        snapshot.confirmedImportProvenances.filter { $0.userId == userId }
    }

    public func removeConfirmedImportEntityReference(
        userId: UUID,
        reference: ConfirmedImportEntityReference
    ) throws {
        var updated: [ConfirmedImportProvenance] = []
        updated.reserveCapacity(snapshot.confirmedImportProvenances.count)
        for provenance in snapshot.confirmedImportProvenances {
            guard provenance.userId == userId else {
                updated.append(provenance)
                continue
            }
            if let remaining = provenance.removingConfirmedEntity(reference) {
                updated.append(remaining)
            }
        }
        snapshot.confirmedImportProvenances = updated
        try persistLocked()
    }

    public func deleteConfirmedImportProvenances(userId: UUID) throws {
        snapshot.confirmedImportProvenances.removeAll { $0.userId == userId }
        try persistLocked()
    }

    // MARK: - Persistence

    public func reloadFromDisk() throws {
        guard let fileURL else { return }
        guard persistenceIO.fileExists(at: fileURL) else {
            snapshot = .empty
            return
        }
        let loaded = try readSnapshotFromDisk(at: fileURL)
        if loaded.schemaVersion > YoushuSnapshot.currentSchemaVersion {
            throw DataError.schemaUnsupported(
                found: loaded.schemaVersion,
                supported: YoushuSnapshot.currentSchemaVersion
            )
        }
        snapshot = loaded
        if snapshot.schemaVersion < YoushuSnapshot.currentSchemaVersion {
            // v1→v2: pending/suspected；v2→v3: consent/recognition/media 缺省空数组；v3→v4: debt inventory establishment 默认 unestablished；v4→v5: confirmedImportProvenances 缺省空数组。
            snapshot.schemaVersion = YoushuSnapshot.currentSchemaVersion
            try persistLocked()
            YoushuLog.data.info("Migrated snapshot to schema=\(snapshot.schemaVersion)")
        }
        YoushuLog.data.info("Loaded snapshot schema=\(snapshot.schemaVersion)")
    }

    public func persist() throws {
        try persistLocked()
    }

    private func persistLocked() throws {
        guard let fileURL else { return }
        do {
            try persistenceIO.createDirectory(at: fileURL.deletingLastPathComponent())
            let data = try encodeSnapshotData(snapshot)
            try persistenceIO.write(data, to: fileURL)
        } catch {
            throw DataError.persistenceFailed(String(describing: error))
        }
    }

    private func encodeSnapshotData(_ snapshot: YoushuSnapshot) throws -> Data {
        try encoder.encode(snapshot)
    }

    private func readSnapshotFromDisk(at fileURL: URL) throws -> YoushuSnapshot {
        let data = try persistenceIO.read(from: fileURL)
        return try decoder.decode(YoushuSnapshot.self, from: data)
    }

    private func snapshotsEqual(_ lhs: YoushuSnapshot, _ rhs: YoushuSnapshot) throws -> Bool {
        let comparisonEncoder = JSONEncoder()
        comparisonEncoder.outputFormatting = [.sortedKeys]
        comparisonEncoder.dateEncodingStrategy = .iso8601
        return try comparisonEncoder.encode(lhs) == comparisonEncoder.encode(rhs)
    }

    private func rollbackRestore(
        previousData: Data,
        previousSnapshot: YoushuSnapshot,
        fileURL: URL,
        causedBy verificationFailure: BackupRestoreError
    ) throws -> Never {
        do {
            try persistenceIO.write(previousData, to: fileURL)
            let rolledBack = try readSnapshotFromDisk(at: fileURL)
            guard try snapshotsEqual(rolledBack, previousSnapshot) else {
                throw BackupRestoreError.rollbackFailed
            }
        } catch let error as BackupRestoreError {
            throw error
        } catch {
            throw BackupRestoreError.rollbackFailed
        }

        throw verificationFailure
    }

    private func removeConfirmedImportEntityReference(_ reference: ConfirmedImportEntityReference) {
        snapshot.confirmedImportProvenances = snapshot.confirmedImportProvenances.compactMap {
            $0.removingConfirmedEntity(reference)
        }
    }

    private func requireUser(_ userId: UUID) throws {
        guard snapshot.users.contains(where: { $0.id == userId }) else {
            throw DataError.invalidRelation("User \(userId) does not exist")
        }
    }

    private func upsert<T: Identifiable>(_ items: inout [T], _ value: T) where T.ID == UUID {
        if let index = items.firstIndex(where: { $0.id == value.id }) {
            items[index] = value
        } else {
            items.append(value)
        }
    }
}
