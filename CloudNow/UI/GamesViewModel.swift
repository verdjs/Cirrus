import Foundation
import Observation
import UIKit

struct ResumableSession {
    let game: GameInfo
    let session: SessionInfo
    let leftAt: Date
    /// Grace window before we stop offering to resume (GFN keeps the session ~2 min).
    static let gracePeriod: TimeInterval = 110

    var secondsRemaining: Int {
        max(0, Int(Self.gracePeriod - Date().timeIntervalSince(leftAt)))
    }
    var isExpired: Bool { secondsRemaining == 0 }
}

@Observable
class GamesViewModel {
    var mainGames: [GameInfo] = []
    var libraryGames: [GameInfo] = []
    var activeSessions: [ActiveSessionInfo] = []
    var isLoading = false
    var error: String?
    var libraryError: String?

    var favoriteIds: Set<String> = []
    var preferredStoreIds: [String: String] = [:]
    var recentlyPlayedIds: [String] = []
    var streamSettings: StreamSettings = StreamSettings()
    var subscription: SubscriptionInfo? = nil
    /// Session the user left without ending — available to resume for ~2 minutes.
    var resumableSession: ResumableSession? = nil
    
    /// The currently active GeForce NOW game being streamed. Drives the full-screen cover in the shell.
    var activeGFNGame: GameInfo? = nil

    private let gamesClient = GamesClient()
    private let cloudMatchClient = CloudMatchClient()

    init() {
        if let data = UserDefaults.standard.data(forKey: "gfn.favoriteIds"),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.favoriteIds = Set(ids)
        }
        if let data = UserDefaults.standard.data(forKey: "gfn.cachedMainGames"),
           let games = try? JSONDecoder().decode([GameInfo].self, from: data) {
            self.mainGames = games
        }
        if let data = UserDefaults.standard.data(forKey: "gfn.cachedLibraryGames"),
           let games = try? JSONDecoder().decode([GameInfo].self, from: data) {
            self.libraryGames = games
        }
        if let data = UserDefaults.standard.data(forKey: "gfn.cachedSubscription"),
           let sub = try? JSONDecoder().decode(SubscriptionInfo.self, from: data) {
            self.subscription = sub
        }
        if let data = UserDefaults.standard.data(forKey: "gfn.preferredStores"),
           let stores = try? JSONDecoder().decode([String: String].self, from: data) {
            self.preferredStoreIds = stores
        }
        if let data = UserDefaults.standard.data(forKey: "gfn.recentlyPlayed"),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.recentlyPlayedIds = ids
        }
        var settings = StreamSettings()
        if let data = UserDefaults.standard.data(forKey: "gfn.streamSettings"),
           let decoded = try? JSONDecoder().decode(StreamSettings.self, from: data) {
            settings = decoded
        }
        
        // Override with individual tvOS specific keys if present in UserDefaults
        if let tvOSRes = UserDefaults.standard.string(forKey: "gfn_stream_resolution") {
            switch tvOSRes {
            case "1080p (FHD)": settings.resolution = "1920x1080"
            case "1440p (QHD)": settings.resolution = "2560x1440"
            case "2160p (4K UHD)": settings.resolution = "3840x2160"
            default: break
            }
        }
        let tvOSFps = UserDefaults.standard.integer(forKey: "gfn_stream_fps")
        if tvOSFps > 0 {
            settings.fps = tvOSFps
        }
        if let tvOSBitrate = UserDefaults.standard.string(forKey: "gfn_stream_bitrate") {
            switch tvOSBitrate {
            case "Auto (Recommended)":
                settings.maxBitrateKbps = 45_000
            case "35 Mbps":
                settings.maxBitrateKbps = 35_000
            case "50 Mbps":
                settings.maxBitrateKbps = 50_000
            case "75 Mbps":
                settings.maxBitrateKbps = 75_000
            default:
                let mbpsString = tvOSBitrate.replacingOccurrences(of: " Mbps", with: "")
                if let mbps = Int(mbpsString) {
                    settings.maxBitrateKbps = mbps * 1000
                }
            }
        }
        self.streamSettings = settings
        
        // tvOS currently caps at 60 Hz; clamp any saved value to the screen maximum.
        // If Apple raises the cap in a future tvOS release this will automatically unlock.
        let screenMax = UIScreen.main.maximumFramesPerSecond
        if streamSettings.fps > screenMax {
            streamSettings.fps = screenMax
        }
    }

    // MARK: Computed — Entitled Resolutions & FPS

    /// Resolution strings available to the current account tier.
    /// Falls back to a standard preset if no subscription data is available.
    var availableResolutions: [String] {
        guard let resos = subscription?.entitledResolutions, !resos.isEmpty else {
            return ["1280x720", "1920x1080"]
        }
        let unique = Array(Set(resos.map(\.resolutionLabel)))
        return unique.sorted {
            let lw = Int($0.split(separator: "x").first ?? "") ?? 0
            let rw = Int($1.split(separator: "x").first ?? "") ?? 0
            return lw < rw
        }
    }

    /// FPS values available for the currently selected resolution, capped to the
    /// screen's maximum refresh rate. Today tvOS caps at 60 Hz; if Apple raises it
    /// in a future update this will automatically expose the higher option.
    var availableFps: [Int] {
        let maxFps = UIScreen.main.maximumFramesPerSecond
        guard let resos = subscription?.entitledResolutions, !resos.isEmpty else {
            return [30, 60].filter { $0 <= maxFps }
        }
        let parts = streamSettings.resolution.split(separator: "x").compactMap { Int($0) }
        let w = parts.first ?? 1920
        let h = parts.last  ?? 1080
        let matching = resos.filter { $0.widthInPixels == w && $0.heightInPixels == h }
        let source = matching.isEmpty ? resos : matching
        return Array(Set(source.map(\.framesPerSecond))).filter { $0 <= maxFps }.sorted()
    }

    // MARK: Computed — Games

    var continuePlaying: [GameInfo] {
        let sessionAppIds = Set(activeSessions.compactMap { $0.appId })
        return mainGames.filter { game in
            game.variants.contains { v in
                guard let appId = v.appId else { return false }
                return sessionAppIds.contains(appId)
            }
        }
    }

    var favoriteGames: [GameInfo] {
        var seen = Set<String>()
        return mainGames.filter { favoriteIds.contains($0.id) && seen.insert($0.id).inserted }
    }

    var recentlyPlayedGames: [GameInfo] {
        let activeIds = Set(continuePlaying.map { $0.id })
        if recentlyPlayedIds.isEmpty {
            // Curated fallback so the recently played row is always filled and gorgeous!
            return Array(mainGames.filter { !activeIds.contains($0.id) }.prefix(6))
        }
        return recentlyPlayedIds.compactMap { id in
            mainGames.first { $0.id == id && !activeIds.contains($0.id) }
        }
    }

    // MARK: Load

    func load(authManager: AuthManager) async {
        isLoading = true
        error = nil
        libraryError = nil
        do {
            let token = try await authManager.resolveToken()
            let streamingUrl = authManager.session?.provider.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
            let base = streamingUrl.hasSuffix("/") ? String(streamingUrl.dropLast()) : streamingUrl

            mainGames = try await gamesClient.fetchMainGames(token: token, streamingBaseUrl: base)

            // Non-fatal — may be empty if no games are linked to account
            do {
                let fetchedLib = try await gamesClient.fetchLibrary(token: token, streamingBaseUrl: base)
                var uniqueGames: [GameInfo] = []
                var seenIds = Set<String>()
                for game in fetchedLib {
                    if seenIds.insert(game.id).inserted {
                        uniqueGames.append(game)
                    }
                }
                for game in mainGames {
                    if game.isInLibrary {
                        if seenIds.insert(game.id).inserted {
                            uniqueGames.append(game)
                        }
                    }
                }
                libraryGames = uniqueGames
            } catch {
                var uniqueGames: [GameInfo] = []
                var seenIds = Set<String>()
                for game in mainGames {
                    if game.isInLibrary {
                        if seenIds.insert(game.id).inserted {
                            uniqueGames.append(game)
                        }
                    }
                }
                libraryGames = uniqueGames
                libraryError = error.localizedDescription
            }

            // Non-fatal — may fail if no active sessions or server returns 404
            activeSessions = (try? await cloudMatchClient.getActiveSessions(token: token, base: base)) ?? []

            // Non-fatal — fetch subscription tier and entitled resolutions
            if let userId = authManager.session?.user.userId {
                let vpcId = (try? await MESClient.shared.fetchVpcId(token: token, base: base)) ?? ""
                let sub = try? await MESClient.shared.fetchSubscription(token: token, vpcId: vpcId, userId: userId)
                print("[MES] tier=\(sub?.membershipTier ?? "nil") resolutions=\(sub?.entitledResolutions.map(\.resolutionLabel) ?? [])")
                subscription = sub
            }
            
            if let mainGamesData = try? JSONEncoder().encode(mainGames) {
                UserDefaults.standard.set(mainGamesData, forKey: "gfn.cachedMainGames")
            }
            if let libraryGamesData = try? JSONEncoder().encode(libraryGames) {
                UserDefaults.standard.set(libraryGamesData, forKey: "gfn.cachedLibraryGames")
            }
            if let sub = subscription, let subData = try? JSONEncoder().encode(sub) {
                UserDefaults.standard.set(subData, forKey: "gfn.cachedSubscription")
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refreshActiveSessions(authManager: AuthManager) async {
        guard let token = try? await authManager.resolveToken() else { return }
        let streamingUrl = authManager.session?.provider.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
        let base = streamingUrl.hasSuffix("/") ? String(streamingUrl.dropLast()) : streamingUrl
        activeSessions = (try? await cloudMatchClient.getActiveSessions(token: token, base: base)) ?? []
    }

    // MARK: Recently Played

    func recordPlayed(_ game: GameInfo) {
        recentlyPlayedIds.removeAll { $0 == game.id }
        recentlyPlayedIds.insert(game.id, at: 0)
        if recentlyPlayedIds.count > 10 { recentlyPlayedIds = Array(recentlyPlayedIds.prefix(10)) }
        let data = try? JSONEncoder().encode(recentlyPlayedIds)
        UserDefaults.standard.set(data, forKey: "gfn.recentlyPlayed")
    }

    // MARK: Preferred Store

    func setPreferredStore(gameId: String, variantId: String) {
        preferredStoreIds[gameId] = variantId
        let data = try? JSONEncoder().encode(preferredStoreIds)
        UserDefaults.standard.set(data, forKey: "gfn.preferredStores")
    }

    func preferredVariantId(for game: GameInfo) -> String? {
        preferredStoreIds[game.id] ?? game.variants.first?.id
    }

    func gameWithPreferredStore(_ game: GameInfo) -> GameInfo {
        guard let preferredId = preferredStoreIds[game.id],
              let idx = game.variants.firstIndex(where: { $0.id == preferredId }),
              idx != 0 else { return game }
        var g = game
        let preferred = g.variants.remove(at: idx)
        g.variants.insert(preferred, at: 0)
        return g
    }

    // MARK: Favorites

    func toggleFavorite(_ id: String) {
        if favoriteIds.contains(id) {
            favoriteIds.remove(id)
        } else {
            favoriteIds.insert(id)
        }
        saveFavorites()
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteIds.contains(id)
    }

    // MARK: Persistence

    func saveFavorites() {
        let data = try? JSONEncoder().encode(Array(favoriteIds))
        UserDefaults.standard.set(data, forKey: "gfn.favoriteIds")
    }

    func saveSettings() {
        let data = try? JSONEncoder().encode(streamSettings)
        UserDefaults.standard.set(data, forKey: "gfn.streamSettings")
    }
}
