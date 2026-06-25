// ConsoleListEmptyState.swift
// Defines the console list empty state.
//

import SwiftUI

extension ConsoleListView {
    var emptyState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "xbox.logo")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(CloudXTheme.Colors.focusTint)
                }
                .frame(width: 110, height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                VStack(spacing: 10) {
                    Text("No Consoles Found")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(CloudXTheme.Colors.textPrimary)

                    Text("Make sure your Xbox is on, signed in to the same account, and has remote features enabled.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(CloudXTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    consoleChecklistRow(icon: "checkmark.shield.fill", text: "Sign in with the same Xbox account used on your console.")
                    consoleChecklistRow(icon: "antenna.radiowaves.left.and.right", text: "Enable remote features in Xbox settings.")
                    consoleChecklistRow(icon: "network", text: "Keep the console connected to the internet.")
                }
                .padding(.top, 4)
            }

            Button {
                Task { await refreshConsoles() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .bold))
                    Text("Refresh Consoles")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }
            .buttonStyle(.bordered)
            .focused($focusedTarget, equals: .refresh)
            .onMoveCommand { direction in
                guard direction == .left else { return }
                onRequestSideRailEntry()
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private func consoleChecklistRow(icon: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(CloudXTheme.Colors.focusTint)
            .frame(width: 18)
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(CloudXTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
