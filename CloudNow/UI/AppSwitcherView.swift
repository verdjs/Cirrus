import SwiftUI

enum AppMode: String, Codable {
    case chooser
    case shieldNow
    case xCloud
}

struct AppSwitcherView: View {
    @Binding var appMode: AppMode
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Premium background gradient
            RadialGradient(
                colors: [
                    Color(red: 0.1, green: 0.25, blue: 0.1).opacity(0.25),
                    Color(red: 0.05, green: 0.05, blue: 0.1).opacity(0.15),
                    Color.black
                ],
                center: .center,
                startRadius: 50,
                endRadius: 900
            )
            .ignoresSafeArea()
            
            VStack(spacing: 50) {
                VStack(spacing: 12) {
                    Image(systemName: "appletv.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.bottom, 10)
                    
                    Text("CLOUDX PORTAL")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(4)
                    
                    Text("Select your cloud gaming experience")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .tracking(1)
                }
                .padding(.top, 40)
                
                HStack(spacing: 48) {
                    AppCard(
                        title: "ShieldNow",
                        subtitle: "GeForce NOW Client",
                        description: "Stream PC gaming titles from your GeForce NOW library with high framerates and low latency.",
                        systemImage: "play.tv.fill",
                        accentColor: Color(red: 0.46, green: 0.73, blue: 0.0), // NVIDIA Green #76B900
                        action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                appMode = .shieldNow
                            }
                        }
                    )
                    
                    AppCard(
                        title: "xCloud",
                        subtitle: "Xbox Cloud Gaming",
                        description: "Access your Xbox Game Pass Ultimate vault directly on Apple TV with native controller support.",
                        systemImage: "cloud.fill",
                        accentColor: Color(red: 0.06, green: 0.49, blue: 0.06), // Xbox Green #107C10
                        action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                appMode = .xCloud
                            }
                        }
                    )
                }
                
                Spacer()
            }
        }
    }
}

struct AppCard: View {
    let title: String
    let subtitle: String
    let description: String
    let systemImage: String
    let accentColor: Color
    let action: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 54))
                        .foregroundStyle(isFocused ? accentColor : .white)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(isFocused ? accentColor.opacity(0.9) : .secondary)
                }
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(32)
            .frame(width: 440, height: 300)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(isFocused ? Color(white: 0.16) : Color(white: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(accentColor.opacity(isFocused ? 1 : 0), lineWidth: 4)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .shadow(color: accentColor.opacity(isFocused ? 0.25 : 0), radius: 24, x: 0, y: 12)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.75), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}
