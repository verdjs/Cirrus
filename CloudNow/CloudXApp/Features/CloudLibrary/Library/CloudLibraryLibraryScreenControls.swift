// CloudLibraryLibraryScreenControls.swift
// Defines cloud library library screen controls for the CloudLibrary / Library surface.
//

import SwiftUI

struct LibraryFilterChipButton: View {
    let chip: ChipViewState
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                if let image = chip.systemImage {
                    Image(systemName: image)
                }
                Text(chip.label)
                    .lineLimit(1)
            }
            .font(CloudXTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(chip.isSelected || chip.style == .accent ? CloudXTheme.Colors.focusTint : nil)
    }
}

struct LibraryTabButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .font(
                    CloudXTypography.rounded(
                        24,
                        weight: isSelected ? .bold : .medium,
                        dynamicTypeSize: dynamicTypeSize
                    )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? CloudXTheme.Colors.focusTint : nil)
    }
}

struct SortButton: View {
    let title: String
    var icon: String = "arrow.up.arrow.down"
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
            }
            .font(CloudXTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}
