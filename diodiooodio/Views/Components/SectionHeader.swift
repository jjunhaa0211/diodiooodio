import SwiftUI

/// SectionHeader 구조체를 정의합니다.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .sectionHeaderStyle()
    }
}

// MARK: - 프리뷰

#Preview("Section Headers") {
    ComponentPreviewContainer {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            SectionHeader(title: "Output Devices")

            SectionHeader(title: "Apps")

            SectionHeader(title: "Active Applications")
        }
    }
}
