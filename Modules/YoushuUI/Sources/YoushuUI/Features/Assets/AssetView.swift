import SwiftUI
import YoushuDesignSystem
import YoushuDomain

public struct AssetView: View {
    @Bindable private var viewModel: AssetViewModel

    public init(viewModel: AssetViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        YSPageContainer(title: "资产", phase: viewModel.phase, onRetry: retry) { snapshot in
            ScrollView {
                VStack(spacing: YSSpacing.md) {
                    YSCard {
                        VStack(alignment: .leading, spacing: YSSpacing.xs) {
                            Text("资产总值")
                                .font(YSTypography.caption)
                                .foregroundStyle(YSColor.Fallback.textSecondary)
                            YSMoneyText(snapshot.totalValue, style: YSTypography.amountLarge, color: YSColor.Fallback.positive)
                        }
                    }
                    YSListSection(title: "资产列表") {
                        ForEach(snapshot.assets, id: \.id) { asset in
                            YSListRow(
                                title: asset.name,
                                subtitle: asset.type.rawValue,
                                trailing: YSMoneyFormatter.string(for: asset.currentValue),
                                icon: "square.stack.3d.up"
                            )
                            if asset.id != snapshot.assets.last?.id {
                                Divider().padding(.leading, YSSpacing.md + 28)
                            }
                        }
                    }
                }
                .padding(.horizontal, YSSpacing.md)
                .padding(.vertical, YSSpacing.sm)
            }
        }
        .task { await viewModel.load() }
    }

    private func retry() {
        Task { await viewModel.load() }
    }
}
