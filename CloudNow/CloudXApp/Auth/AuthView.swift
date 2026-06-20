// AuthView.swift
// Defines the signed-out landing screen and the first-step Microsoft sign-in call to action.
//

import SwiftUI
import CloudXCore

/// Presents the signed-out shell and starts the device-code login flow.
struct AuthView: View {
    @Environment(SessionController.self) private var sessionController
    @FocusState private var isSignInFocused: Bool
    @State private var focusSettler = FocusSettleDebouncer()
    @State private var pendingFocusTask: Task<Void, Never>?

    /// Builds the signed-out landing screen, including the focused sign-in CTA and auth errors.
    var body: some View {
        ZStack {
            CloudLibraryAmbientBackground(imageURL: nil)

            LinearGradient(
                colors: [Color.black.opacity(0.7), Color(red: 0.01, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    ClosePortalButton {
                        NotificationCenter.default.post(name: Notification.Name("CloudXPortalReturnNotification"), object: nil)
                    }
                    .padding(.leading, 80)
                    .padding(.top, 60)
                    Spacer()
                }
                Spacer()
            }

            VStack(spacing: 40) {
                VStack(spacing: 12) {
                    CloudXAppIcon()
                        .frame(width: 180, height: 180)

                    Text("CloudX")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Sign in with your Microsoft account to stream xCloud titles.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 720)
                }

                if let error = sessionController.lastAuthError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(CloudXTheme.Colors.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: {
                    Task { await sessionController.beginSignIn() }
                }) {
                    Label("Sign In With Microsoft", systemImage: "person.badge.key")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .focused($isSignInFocused)
                .accessibilityIdentifier("auth_sign_in_button")
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 56)
            .frame(maxWidth: 1000)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 18)
        }
        .accessibilityIdentifier("auth_root")
        .onAppear {
            pendingFocusTask?.cancel()
            pendingFocusTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                isSignInFocused = true
            }
        }
        .onChange(of: isSignInFocused) { _, isFocused in
            focusSettler.cancel()
            if isFocused {
                NavigationPerformanceTracker.recordFocusTarget(surface: "auth", target: "sign_in")
                focusSettler.schedule(debounce: CloudXConstants.Timing.focusTargetDebounceNanoseconds) {
                    NavigationPerformanceTracker.recordFocusSettled(surface: "auth", target: "sign_in")
                }
            } else {
                NavigationPerformanceTracker.recordFocusLoss(surface: "auth")
            }
        }
        .onMoveCommand { direction in
            NavigationPerformanceTracker.recordRemoteMoveStart(surface: "auth", direction: direction)
        }
        .onDisappear {
            focusSettler.cancel()
        }
    }
}

#if DEBUG
#Preview("AuthView", traits: .fixedLayout(width: 1920, height: 1080)) {
    let coordinator = AppCoordinator()
    AuthView()
        .environment(coordinator.sessionController)
}
#endif

fileprivate struct ClosePortalButton: View {
    let action: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(isFocused ? .black : .white)
                .frame(width: 64, height: 64)
                .background(isFocused ? Color.white : Color.white.opacity(0.12))
                .clipShape(Circle())
                .scaleEffect(isFocused ? 1.15 : 1.0)
                .shadow(color: Color.black.opacity(isFocused ? 0.3 : 0), radius: 10, x: 0, y: 5)
                .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.7), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

