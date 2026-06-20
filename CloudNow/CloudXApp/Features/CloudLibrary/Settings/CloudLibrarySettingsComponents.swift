// CloudLibrarySettingsComponents.swift
// Defines cloud library settings components for the CloudLibrary / Settings surface.
//

import SwiftUI

struct CloudLibraryPageSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(Color.primary.opacity(0.6))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)

            content
        }
        .padding(.vertical, 12)
    }
}

struct CloudLibrarySidebarButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(CloudXTypography.rounded(21, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? Color.primary.opacity(0.15) : nil)
        .accessibilityValue(Text(isSelected ? "selected" : "not_selected"))
    }
}

struct CloudLibrarySettingsActionButton: View {
    let title: String
    let systemImage: String
    var destructive = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(CloudXTypography.rounded(19, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .foregroundStyle(destructive ? Color.white : Color.primary)
        }
        .buttonStyle(.bordered)
        .tint(destructive ? Color.red.opacity(0.8) : nil)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct CloudLibraryToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CloudXTypography.rounded(21, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(Color.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(CloudXTypography.rounded(15, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}

struct CloudLibrarySliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatter: (Double) -> String
    var step: Double? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resolvedStep: Double {
        let fallback = (range.upperBound - range.lowerBound) / 20
        return max(step ?? fallback, 0.01)
    }

    private var normalized: Double {
        guard range.upperBound > range.lowerBound else { return 1 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(CloudXTypography.rounded(21, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(Color.primary)

                    Spacer()

                    Text(formatter(value))
                        .font(CloudXTypography.rounded(17, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(CloudXTheme.Colors.focusTint)
                        .monospacedDigit()
                }

                ProgressView(value: max(0, min(1, normalized)))
                    .tint(CloudXTheme.Colors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .onMoveCommand { direction in
            if direction == .left {
                value = max(range.lowerBound, value - resolvedStep)
            } else if direction == .right {
                value = min(range.upperBound, value + resolvedStep)
            }
        }
    }
}

struct CloudLibraryPickerRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack {
            Text(title)
                .font(CloudXTypography.rounded(21, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(Color.primary)
            
            Spacer()
            
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

struct CloudLibraryStatPill: View {
    let icon: String
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Label(text, systemImage: icon)
            .font(CloudXTypography.rounded(13, weight: .bold, dynamicTypeSize: dynamicTypeSize))
            .foregroundStyle(CloudXTheme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct CloudLibraryStatLine: View {
    let icon: String
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CloudXTheme.Colors.focusTint)
                .frame(width: 20)

            Text(text)
                .font(CloudXTypography.rounded(15, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(CloudXTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CloudLibrarySettingTag: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(CloudXTypography.rounded(10, weight: .bold, dynamicTypeSize: dynamicTypeSize))
            .foregroundStyle(CloudXTheme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}
