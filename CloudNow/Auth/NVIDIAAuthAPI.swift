import CryptoKit
import Foundation
import Security

// MARK: - Constants

nonisolated enum NVIDIAAuth {
    nonisolated static let authEndpoint    = "https://login.nvidia.com/authorize"
    nonisolated static let tokenEndpoint   = "https://login.nvidia.com/token"
    nonisolated static let deviceAuthorizeEndpoint = "https://login.nvidia.com/device/authorize"
    nonisolated static let clientTokenEndpoint = "https://login.nvidia.com/client_token"
    nonisolated static let userinfoEndpoint = "https://login.nvidia.com/userinfo"
    nonisolated static let serviceUrlsEndpoint = "https://pcs.geforcenow.com/v1/serviceUrls"

    nonisolated static let clientID = "W1Z7DwzG1dcpXFxv0pmeatjnf0uK3ICySganqdMx2nU"
    nonisolated static let deviceFlowClientID = "W1Z7DwzG1dcpXFxv0pmeatjnf0uK3ICySganqdMx2nU"
    nonisolated static let scopes   = "openid consent email tk_client age"
    nonisolated static let defaultIdpId = "SBcX86bSGvOo6kgTpV_dRtqSs_3uU0hsK3r1JZGQElo"
    nonisolated static let defaultStreamingUrl = "https://prod.cloudmatchbeta.nvidiagrid.net/"
    nonisolated static let callbackScheme = "http"

    // Matches the official GFN PC client User-Agent so the NVIDIA backend accepts the token
    nonisolated static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 NVIDIACEFClient/HEAD/debb5919f6 GFN-PC/2.0.83.130"
}

// MARK: - PKCE Helpers

nonisolated struct PKCE {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(86)
        let verifierStr = String(verifier)
        let challengeData = SHA256.hash(data: Data(verifierStr.utf8))
        let challenge = Data(challengeData)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return PKCE(verifier: verifierStr, challenge: challenge)
    }
}

// MARK: - Keychain

nonisolated enum KeychainService {
    private static let service = "com.owenselles.CloudNow"
    private static let account = "gfn-auth-session"

    static func save(_ data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return data
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
    }
}

// MARK: - Response Models

nonisolated struct AuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date
    var clientToken: String?
    var clientTokenExpiresAt: Date?

    var isExpired: Bool { expiresAt < Date() }
    var isNearExpiry: Bool { expiresAt.timeIntervalSinceNow < 10 * 60 }
}

nonisolated struct AuthUser: Codable {
    let userId: String
    let displayName: String
    let email: String?
    let avatarUrl: String?
    var membershipTier: String
}

nonisolated struct DeviceFlowResponse: Codable {
    let userCode: String
    let deviceCode: String
    let verificationUri: String
    let verificationUriComplete: String
    let expiresIn: Int
    let interval: Int
}

nonisolated struct LoginProvider: Codable {
    let idpId: String
    let code: String
    let displayName: String
    var streamingServiceUrl: String
    let priority: Int
}

// MARK: - NVIDIA OAuth API

actor NVIDIAAuthAPI {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": NVIDIAAuth.userAgent]
        return URLSession(configuration: config)
    }()

    // MARK: Providers

    func fetchProviders() async throws -> [LoginProvider] {
        var request = URLRequest(url: URL(string: NVIDIAAuth.serviceUrlsEndpoint)!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        let payload = try JSONDecoder().decode(ServiceUrlsResponse.self, from: data)
        
        // Filter out StarHub ("STR") as they collapsed
        let endpoints = (payload.gfnServiceInfo?.gfnServiceEndpoints ?? []).filter { $0.loginProviderCode != "STR" }
        let preferred = payload.loginPreferredProviders ?? []
        
        var countryCode = payload.clientCountryCode ?? payload.requestStatus?.countryCode ?? ""
        if countryCode.isEmpty {
            countryCode = Locale.current.region?.identifier ?? ""
        }
        let countryToProvider: [String: String] = [
            "AU": "PNT", "NZ": "PNT",
            "MY": "YES",
            "TR": "TKC",
            "JP": "KDD",
            "KR": "GKR",
            "TW": "TWM", "HK": "TWM",
            "BR": "ABY", "AR": "ABY", "UY": "ABY", "PY": "ABY",
            "ZA": "RAN",
            "AM": "GCS", "AZ": "GCS", "GE": "GCS", "KZ": "GCS"
        ]
        let countryPreferredCode = countryToProvider[countryCode.uppercased()]
        
        return endpoints.map { entry in
            let isPreferred = preferred.contains(entry.loginProviderDisplayName) || 
                              preferred.contains(entry.loginProviderCode) ||
                              preferred.contains(entry.loginProvider ?? "")
            
            let priority: Int
            if entry.loginProviderCode == countryPreferredCode {
                priority = -2 // Highest priority (geo-located country match)
            } else if isPreferred {
                priority = -1 // Second highest priority (server preferred)
            } else {
                priority = entry.loginProviderPriority ?? 0
            }
            
            return LoginProvider(
                idpId: entry.idpId,
                code: entry.loginProviderCode,
                displayName: entry.loginProviderCode == "BPC" ? "bro.game" : entry.loginProviderDisplayName,
                streamingServiceUrl: entry.streamingServiceUrl.hasSuffix("/") ? entry.streamingServiceUrl : "\(entry.streamingServiceUrl)/",
                priority: priority
            )
        }.sorted { $0.priority < $1.priority }
    }

    // MARK: Token Exchange

    func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> AuthTokens {
        var request = URLRequest(url: URL(string: NVIDIAAuth.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://nvfile", forHTTPHeaderField: "Origin")
        request.setValue("https://nvfile/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&code_verifier=\(verifier)"
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GFNAuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "")
        }
        return try parseTokenResponse(data)
    }

    // MARK: Token Refresh

    func refreshTokens(_ refreshToken: String) async throws -> AuthTokens {
        var request = URLRequest(url: URL(string: NVIDIAAuth.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://nvfile", forHTTPHeaderField: "Origin")
        // Try the main clientID first. If NVIDIA rejects it with a 4xx (token bound to
        // deviceFlowClientID because the rebind step at login didn't return a new refreshToken),
        // retry with the device-flow clientID as a fallback.
        for clientID in [NVIDIAAuth.clientID, NVIDIAAuth.deviceFlowClientID] {
            request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)".data(using: .utf8)
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200 {
                return try parseTokenResponse(data)
            }
            // Server-side error (5xx) or unexpected status — no point retrying with another clientID
            if statusCode < 400 || statusCode >= 500 {
                throw GFNAuthError.tokenRefreshFailed(String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)")
            }
            // 4xx → token rejected for this clientID; try the next one
        }
        throw GFNAuthError.tokenRefreshFailed("Refresh token rejected by all known client IDs.")
    }

    // MARK: Client Token

    func fetchClientToken(accessToken: String) async throws -> (token: String, expiresAt: Date) {
        var request = URLRequest(url: URL(string: NVIDIAAuth.clientTokenEndpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("https://nvfile", forHTTPHeaderField: "Origin")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            throw GFNAuthError.clientTokenFailed("HTTP \(statusCode): \(body)")
        }
        let payload = try JSONDecoder().decode(ClientTokenResponse.self, from: data)
        let expiresAt = Date().addingTimeInterval(TimeInterval(payload.expires_in ?? 86400))
        return (payload.client_token, expiresAt)
    }

    /// Exchanges a client_token for fresh OAuth tokens bound to the main clientID.
    /// This is the primary refresh mechanism used by the official GFN client and
    /// re-binds tokens regardless of which OAuth client originally issued them
    /// (e.g. device flow client → main client).
    func refreshWithClientToken(_ clientToken: String, userId: String) async throws -> AuthTokens {
        var request = URLRequest(url: URL(string: NVIDIAAuth.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://nvfile", forHTTPHeaderField: "Origin")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        // Try main clientID first, then device-flow clientID as fallback.
        // The stored clientToken may have been issued under either, depending on
        // which step of the login flow succeeded.
        var lastError: Error = GFNAuthError.clientTokenFailed("No client IDs tried")
        for clientID in [NVIDIAAuth.clientID, NVIDIAAuth.deviceFlowClientID] {
            let body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Aclient_token&client_token=\(clientToken)&client_id=\(clientID)&sub=\(userId)"
            request.httpBody = body.data(using: .utf8)
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200 { return try parseTokenResponse(data) }
            let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"
            lastError = GFNAuthError.clientTokenFailed("HTTP \(statusCode): \(responseBody)")
            if statusCode < 400 || statusCode >= 500 { throw lastError }
            // 4xx with clientID mismatch → try next clientID
        }
        throw lastError
    }

    // MARK: Device Flow (PIN-based login)

    func requestDeviceAuthorization(idpId: String? = nil) async throws -> DeviceFlowResponse {
        var request = URLRequest(url: URL(string: NVIDIAAuth.deviceAuthorizeEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var params = "client_id=\(NVIDIAAuth.deviceFlowClientID)&scope=\(NVIDIAAuth.scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? NVIDIAAuth.scopes)&device_id=\(UUID().uuidString)&display_name=Apple%20TV"
        if let idpId {
            params += "&idp_id=\(idpId)"
        }
        request.httpBody = params.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GFNAuthError.deviceFlowFailed(String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DeviceFlowResponse.self, from: data)
    }

    func pollForDeviceToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> AuthTokens {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var pollInterval = TimeInterval(interval)

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            try Task.checkCancellation()

            var request = URLRequest(url: URL(string: NVIDIAAuth.tokenEndpoint)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code&device_code=\(deviceCode)&client_id=\(NVIDIAAuth.deviceFlowClientID)"
            request.httpBody = body.data(using: .utf8)
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 200 {
                return try parseTokenResponse(data)
            }

            // Parse error response
            if let errorResp = try? JSONDecoder().decode(DeviceFlowErrorResponse.self, from: data) {
                switch errorResp.error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    pollInterval += 5
                    continue
                case "expired_token":
                    throw GFNAuthError.deviceFlowExpired
                case "access_denied":
                    throw GFNAuthError.deviceFlowDenied
                default:
                    throw GFNAuthError.deviceFlowFailed(errorResp.errorDescription ?? errorResp.error)
                }
            }
        }
        throw GFNAuthError.deviceFlowExpired
    }

    // MARK: User Info

    func fetchUserInfo(tokens: AuthTokens) async throws -> AuthUser {
        // Try JWT payload first (fast path)
        let jwt = tokens.idToken ?? tokens.accessToken
        if let user = parseUserFromJWT(jwt) { return user }

        var request = URLRequest(url: URL(string: NVIDIAAuth.userinfoEndpoint)!)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("https://nvfile", forHTTPHeaderField: "Origin")
        let (data, _) = try await session.data(for: request)
        let payload = try JSONDecoder().decode(UserinfoResponse.self, from: data)
        return AuthUser(
            userId: payload.sub,
            displayName: payload.preferred_username ?? payload.email?.components(separatedBy: "@").first ?? "User",
            email: payload.email,
            avatarUrl: nil,
            membershipTier: "FREE"
        )
    }

    // MARK: Private Helpers

    private func parseTokenResponse(_ data: Data) throws -> AuthTokens {
        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthTokens(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            idToken: payload.id_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in ?? 86400)),
            clientToken: payload.client_token,
            clientTokenExpiresAt: payload.client_token_expires_in.map {
                Date().addingTimeInterval(TimeInterval($0))
            }
        )
    }

    private func parseUserFromJWT(_ jwt: String) -> AuthUser? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: data),
              let sub = payload.sub
        else { return nil }
        return AuthUser(
            userId: sub,
            displayName: payload.preferred_username ?? payload.email?.components(separatedBy: "@").first ?? "User",
            email: payload.email,
            avatarUrl: payload.picture,
            membershipTier: payload.gfn_tier ?? "FREE"
        )
    }

    nonisolated private func randomHex(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Codable Response Types

nonisolated private struct ServiceUrlsResponse: Decodable {
    struct RequestStatus: Decodable {
        let countryCode: String?
    }
    let requestStatus: RequestStatus?
    let gfnServiceInfo: GFNServiceInfo?
    let clientCountryCode: String?
    let loginPreferredProviders: [String]?
    nonisolated struct GFNServiceInfo: Decodable {
        let gfnServiceEndpoints: [Endpoint]?
        nonisolated struct Endpoint: Decodable {
            let idpId: String
            let loginProviderCode: String
            let loginProviderDisplayName: String
            let loginProvider: String?
            let streamingServiceUrl: String
            let loginProviderPriority: Int?
        }
    }
}

extension LoginProvider: Identifiable, Hashable {
    public var id: String { code }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
    
    public static func == (lhs: LoginProvider, rhs: LoginProvider) -> Bool {
        lhs.code == rhs.code
    }
    
    public var regionLabel: String {
        switch code {
        case "NVIDIA": return "Global (US, Europe, direct)"
        case "KDD": return "Japan (au)"
        case "TWM": return "Taiwan & SE Asia (Taiwan Mobile)"
        case "ZAI": return "Middle East (Zain)"
        case "TKC": return "Turkey (GAME+)"
        case "STR": return "Singapore (StarHub)"
        case "DIG": return "Latin America (Digevo)"
        case "ABY": return "South America (ABYA)"
        case "PNT": return "Australia & NZ (Cloud.GG)"
        case "YES": return "Malaysia (YES)"
        case "GCS": return "Armenia & CIS (GFN.AM)"
        case "RAN": return "South Africa (rain)"
        case "GKR": return "South Korea"
        case "BPC": return "Russia (Brothers)"
        default: return displayName
        }
    }
}

nonisolated private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let id_token: String?
    let expires_in: Int?
    let client_token: String?
    let client_token_expires_in: Int?
}

nonisolated private struct ClientTokenResponse: Decodable {
    let client_token: String
    let expires_in: Int?
}

nonisolated private struct UserinfoResponse: Decodable {
    let sub: String
    let preferred_username: String?
    let email: String?
}

nonisolated private struct DeviceFlowErrorResponse: Decodable {
    let error: String
    let errorDescription: String?
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

nonisolated private struct JWTPayload: Decodable {
    let sub: String?
    let email: String?
    let preferred_username: String?
    let picture: String?
    let gfn_tier: String?
}

// MARK: - Errors

enum GFNAuthError: Error, LocalizedError {
    case noAuthCode
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case clientTokenFailed(String)
    case noSession
    case deviceFlowFailed(String)
    case deviceFlowExpired
    case deviceFlowDenied

    var errorDescription: String? {
        switch self {
        case .noAuthCode: return "No authorization code received."
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .tokenRefreshFailed(let msg): return "Token refresh failed: \(msg)"
        case .clientTokenFailed(let msg): return "Failed to obtain client token: \(msg)"
        case .noSession: return "No authenticated session."
        case .deviceFlowFailed(let msg): return "Device login failed: \(msg)"
        case .deviceFlowExpired: return "Login code expired. Please try again."
        case .deviceFlowDenied: return "Login was denied."
        }
    }
}
