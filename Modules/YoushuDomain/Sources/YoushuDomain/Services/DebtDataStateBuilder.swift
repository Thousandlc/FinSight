import Foundation

import YoushuFoundation



/// Deterministic mapper from existing debt inventory to canonical `DebtDataState`.

/// Does not use AI output, sourceLabels, or monthlyDebtPayment alone for knownNoDebt.

public enum DebtDataStateBuilder {

    /// Legacy semantic coverage bucket derived from load + establishment. Prefer `SemanticInput` in production.

    public enum InventoryCoverage: Sendable, Equatable {

        case unavailable

        case partial

        case complete

    }



    public struct SemanticInput: Sendable, Equatable {

        public var debts: [Debt]

        public var totalOutstanding: Money

        public var repositoryLoadState: DebtInventoryLoadState

        public var inventoryEstablishment: DebtInventoryEstablishmentState

        public var importInProgress: Bool

        public var monthlyDebtPayment: Money



        public init(

            debts: [Debt],

            totalOutstanding: Money,

            repositoryLoadState: DebtInventoryLoadState,

            inventoryEstablishment: DebtInventoryEstablishmentState,

            importInProgress: Bool = false,

            monthlyDebtPayment: Money = .zeroCNY

        ) {

            self.debts = debts

            self.totalOutstanding = totalOutstanding

            self.repositoryLoadState = repositoryLoadState

            self.inventoryEstablishment = inventoryEstablishment

            self.importInProgress = importInProgress

            self.monthlyDebtPayment = monthlyDebtPayment

        }

    }



    public struct Input: Sendable, Equatable {

        public var debts: [Debt]

        public var totalOutstanding: Money

        public var inventoryCoverage: InventoryCoverage

        public var monthlyDebtPayment: Money



        public init(

            debts: [Debt],

            totalOutstanding: Money,

            inventoryCoverage: InventoryCoverage,

            monthlyDebtPayment: Money = .zeroCNY

        ) {

            self.debts = debts

            self.totalOutstanding = totalOutstanding

            self.inventoryCoverage = inventoryCoverage

            self.monthlyDebtPayment = monthlyDebtPayment

        }

    }



    public static let lowProfileCompletenessThreshold: Double = 0.4



    public static func build(_ input: SemanticInput) -> DebtDataState {

        if input.repositoryLoadState == .failed {

            return .missing

        }

        if input.importInProgress {

            return classifyDuringImport(input)

        }

        switch input.inventoryEstablishment {

        case .unestablished:

            return classifyUnestablished(input)

        case .partial:

            return .partial

        case .confirmedComplete:

            return classifyConfirmedComplete(input)

        }

    }



    public static func build(_ input: Input) -> DebtDataState {

        let semantic = semanticInput(fromLegacy: input)

        return build(semantic)

    }



    public static func build(

        debts: [Debt],

        inventoryCoverage: InventoryCoverage,

        monthlyDebtPayment: Money = .zeroCNY

    ) -> DebtDataState {

        build(

            Input(

                debts: debts,

                totalOutstanding: DebtBalanceCalculator.totalOutstanding(debts: debts),

                inventoryCoverage: inventoryCoverage,

                monthlyDebtPayment: monthlyDebtPayment

            )

        )

    }



    // MARK: - Private



    private static func semanticInput(fromLegacy input: Input) -> SemanticInput {

        let (loadState, establishment): (DebtInventoryLoadState, DebtInventoryEstablishmentState) = switch input.inventoryCoverage {

        case .unavailable:

            (.failed, .unestablished)

        case .partial:

            (.loaded, .partial)

        case .complete:

            (.loaded, .confirmedComplete)

        }

        return SemanticInput(

            debts: input.debts,

            totalOutstanding: input.totalOutstanding,

            repositoryLoadState: loadState,

            inventoryEstablishment: establishment,

            monthlyDebtPayment: input.monthlyDebtPayment

        )

    }



    private static func classifyDuringImport(_ input: SemanticInput) -> DebtDataState {

        let openDebts = input.debts.filter { DebtCenterCalculator.isOpen($0) }

        if !openDebts.isEmpty

            || input.totalOutstanding.amount > 0

            || input.monthlyDebtPayment.amount > 0 {

            return .partial

        }

        return .missing

    }



    private static func classifyUnestablished(_ input: SemanticInput) -> DebtDataState {

        let openDebts = input.debts.filter { DebtCenterCalculator.isOpen($0) }

        if !openDebts.isEmpty || input.totalOutstanding.amount > 0 {

            return .partial

        }

        if input.monthlyDebtPayment.amount > 0 {

            return .partial

        }

        return .missing

    }



    private static func classifyConfirmedComplete(_ input: SemanticInput) -> DebtDataState {

        let openDebts = input.debts.filter { DebtCenterCalculator.isOpen($0) }

        let hasOpenDebtRecords = !openDebts.isEmpty

        let hasOutstanding = input.totalOutstanding.amount > 0



        if hasRepaymentWithoutInventory(input: input, openDebts: openDebts) {

            return .partial

        }



        if !hasOpenDebtRecords, !hasOutstanding {

            return .knownNoDebt

        }



        if hasIncompleteOpenDebtProfile(openDebts) {

            return .partial

        }



        return .knownDebt

    }



    private static func hasRepaymentWithoutInventory(input: SemanticInput, openDebts: [Debt]) -> Bool {

        openDebts.isEmpty

            && input.totalOutstanding.amount == 0

            && input.monthlyDebtPayment.amount > 0

    }



    private static func hasIncompleteOpenDebtProfile(_ openDebts: [Debt]) -> Bool {

        guard !openDebts.isEmpty else { return false }

        return openDebts.contains { $0.profileCompleteness < lowProfileCompletenessThreshold }

    }

}


