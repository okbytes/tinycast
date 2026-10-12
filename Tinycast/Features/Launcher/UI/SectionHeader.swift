import SwiftUI

/// Section label above a group of rows, shared by every palette list.
struct SectionHeader: View {
    @Environment(\.metrics) private var metrics
    let title: String
    /// The first header hugs the top; later ones get spacing above, reading as below.
    var isFirst = false

    var body: some View {
        Text(title)
            .lineLimit(1)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.spacing.md)
            .padding(.top, isFirst ? metrics.spacing.xs : metrics.spacing.sectionSpacing)
            .padding(.bottom, metrics.spacing.sectionHeaderBottom)
    }
}
