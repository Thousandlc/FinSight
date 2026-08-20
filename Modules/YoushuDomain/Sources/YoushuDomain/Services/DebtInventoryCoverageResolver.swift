import Foundation



/// Maps repository load + inventory establishment semantics to legacy `InventoryCoverage` for completeness wiring.

public enum DebtInventoryCoverageResolver {

    public static func inventoryCoverage(

        loadState: DebtInventoryLoadState,

        establishment: DebtInventoryEstablishmentState,

        importInProgress: Bool

    ) -> DebtDataStateBuilder.InventoryCoverage {

        if loadState == .failed {

            return .unavailable

        }

        if importInProgress {

            return .partial

        }

        switch establishment {

        case .unestablished:

            return .unavailable

        case .partial:

            return .partial

        case .confirmedComplete:

            return .complete

        }

    }



    /// Backward-compatible helper; production should pass explicit load + establishment.

    public static func inventoryCoverage(loadSucceeded: Bool) -> DebtDataStateBuilder.InventoryCoverage {

        inventoryCoverage(

            loadState: loadSucceeded ? .loaded : .failed,

            establishment: .unestablished,

            importInProgress: false

        )

    }

}


