import Foundation
import YoushuDomain

public enum GatewayAnswerDraftMapper {
    public static func toDomain(_ dto: GatewayAssistantAnswerDraftDTO) -> AssistantAnswerDraft {
        AssistantAnswerDraft(
            title: dto.title,
            body: dto.body,
            answer: dto.answer,
            citedFactKeys: dto.citedFactKeys,
            disclaimer: dto.disclaimer,
            unknowns: dto.unknowns,
            confidence: dto.confidence,
            keyFacts: dto.keyFacts,
            warnings: dto.warnings,
            actions: dto.actions,
            references: dto.references
        )
    }
}
