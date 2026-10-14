import SwiftUI

/// A dictionary page: headword, then numbered senses hung off a shared gutter, then its sections.
struct DictionaryEntryView: View {
    let entry: DictionaryEntry

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(entry.blocks.indices, id: \.self) { index in
                    DictionaryBlockView(block: entry.blocks[index], leadsPage: index == 0)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xxl)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        // A new term starts at its headword, not wherever the last one was scrolled to.
        .id(entry.term)
    }
}

private struct DictionaryBlockView: View {
    let block: DictionaryEntry.Block
    let leadsPage: Bool

    /// Sense numbers hang in it, so every definition, bullet and note starts on one line.
    private var gutter: CGFloat { Theme.Spacing.xxl }
    private var textColumn: CGFloat { gutter + Theme.Spacing.sm }

    var body: some View {
        switch block {
        case .headword(let word, let homograph, let pronunciation):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                    Text(word)
                        .font(Theme.Typography.calcResult.weight(.bold))
                    if let homograph {
                        Text(homograph)
                            .font(Theme.Typography.keyCap)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .baselineOffset(Theme.Spacing.md)
                    }
                }
                if let pronunciation {
                    Text("| \(pronunciation) |")
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            // A homograph's page follows the one before it, so it needs the room of a new entry.
            .padding(.top, leadsPage ? 0 : Theme.Spacing.xxxl)
        case .partOfSpeech(let runs):
            Text(runs.attributed(base: Theme.Colors.textSecondary))
                .font(Theme.Typography.rowTrailing)
                .padding(.top, Theme.Spacing.xs)
        case .sense(let number, let runs):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(number ?? "")
                    .font(Theme.Typography.rowTitle.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: gutter, alignment: .trailing)
                Text(runs.attributed())
                    .font(Theme.Typography.rowTitle)
            }
        case .subsense(let runs):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("•")
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(runs.attributed())
            }
            .font(Theme.Typography.rowTitle)
            .padding(.leading, textColumn)
        case .note(let runs):
            Text(runs.attributed(base: Theme.Colors.textSecondary))
                .font(Theme.Typography.rowTrailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(noteShape.fill(Theme.Colors.cardFill))
                .overlay(noteShape.strokeBorder(Theme.Colors.cardStroke))
                .padding(.leading, textColumn)
        case .section(let title):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
            }
            .padding(.top, Theme.Spacing.xl)
        case .phrase(let runs):
            Text(runs.attributed())
                .font(Theme.Typography.rowTitle)
                .padding(.top, Theme.Spacing.xs)
        case .paragraph(let runs):
            Text(runs.attributed())
                .font(Theme.Typography.rowTitle)
                .padding(.leading, textColumn)
        }
    }

    private var noteShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
    }
}

extension [DictionaryEntry.Run] {
    /// Styles by intent rather than by font, so each run keeps the size its block sets.
    fileprivate func attributed(base: Color = Theme.Colors.textPrimary) -> AttributedString {
        reduce(into: AttributedString()) { result, run in
            var piece = AttributedString(run.text)
            piece.foregroundColor = base
            switch run.style {
            case .plain: break
            case .example:
                piece.inlinePresentationIntent = .emphasized
                piece.foregroundColor = Theme.Colors.textSecondary
            case .label: piece.foregroundColor = Theme.Colors.textSecondary
            case .strong:
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = Theme.Colors.textPrimary
            case .italic: piece.inlinePresentationIntent = .emphasized
            }
            result.append(piece)
        }
    }
}
