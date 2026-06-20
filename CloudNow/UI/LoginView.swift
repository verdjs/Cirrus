import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) var authManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.01, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if !authManager.providers.isEmpty {
                    HStack(spacing: 20) {
                        Text("Login Region:")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        Menu {
                            ForEach(authManager.providers) { provider in
                                Button {
                                    authManager.selectProvider(provider)
                                } label: {
                                    Text("\(provider.displayName) (\(provider.regionLabel))")
                                }
                            }
                        } label: {
                            HStack {
                                Text(authManager.selectedProvider?.displayName ?? "Select Region")
                                    .font(.headline.weight(.semibold))
                                Image(systemName: "chevron.down")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 80) // Pushes it safely below the tvOS overscan area
                    .padding(.bottom, 20)
                }
                
                Spacer()
                
                switch authManager.loginPhase {
                case .idle:
                    loginPrompt
                case .showingPIN(let code, let url, let urlComplete):
                    pinView(code: code, url: url, urlComplete: urlComplete)
                case .exchangingTokens:
                    exchangingView
                case .failed(let message):
                    failedView(message: message)
                }
                
                Spacer()
            }
            
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
        }
        .task {
            await authManager.loadProviders()
        }
        .onChange(of: authManager.selectedProvider) { _, newProvider in
            if let newProvider, authManager.loginPhase != .idle {
                authManager.login(with: newProvider)
            }
        }
    }

    // MARK: - Login Prompt

    private var loginPrompt: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                Text("CloudNow")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("GeForce NOW for Apple TV")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button {
                authManager.login(with: authManager.selectedProvider)
            } label: {
                Label("Sign in with \(authManager.selectedProvider?.displayName ?? "GeForce NOW")", systemImage: "person.badge.key")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.bordered)
            .tint(.green)
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

    // MARK: - PIN Display

    private func pinView(code: String, url: String, urlComplete: String) -> some View {
        HStack(spacing: 56) {
            // Left: QR code
            VStack(spacing: 20) {
                Text("Scan To Sign In")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                if let qrImage = generateQRCode(from: urlComplete) {
                    qrImage
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 260)
                        .padding(18)
                        .background(Color.white)
                        .cornerRadius(28)
                }

                Text("Scan the QR code with your phone camera to open the activation page.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(32)
            .background(Color.white.opacity(0.06))
            .cornerRadius(28)

            // Right: Manual activation instructions & PIN
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                    Text("Sign In To GeForce NOW")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("If the QR code doesn't open, visit:")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(url)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter this code")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatPIN(code))
                        .font(.system(size: 64, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(18)
                }

                HStack(spacing: 18) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.35)
                    Text("Waiting for authorization...")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Button("Cancel") {
                    authManager.cancelLogin()
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .padding(.top, 16)
            }
            .padding(40)
            .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.04))
            .cornerRadius(28)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 44)
    }

    // MARK: - Exchanging Tokens

    private var exchangingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .tint(.white)
            Text("Signing in...")
                .font(.title2)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)
            Text("Sign In Failed")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                Button("Try Again") {
                    authManager.login(with: authManager.selectedProvider)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button("Cancel") {
                    authManager.cancelLogin()
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
        }
        .padding(40)
    }

    // MARK: - Helpers

    private func formatPIN(_ code: String) -> String {
        guard code.count == 8 else { return code }
        let left = code.prefix(4)
        let right = code.suffix(4)
        return "\(left) \u{2014} \(right)"
    }

    private func generateQRCode(from string: String) -> Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}

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
