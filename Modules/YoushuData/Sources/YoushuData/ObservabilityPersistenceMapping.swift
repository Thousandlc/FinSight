import Foundation
import YoushuFoundation

extension DataError: ObservabilityClassifiable {
    public var observabilityClassification: ObservabilityClassification {
        switch self {
        case .persistenceFailed, .schemaUnsupported:
            return ObservabilityErrorMapping.classify(
                code: .persistenceFailure,
                stage: .insightPersistence
            )
        default:
            return .unclassified
        }
    }
}
