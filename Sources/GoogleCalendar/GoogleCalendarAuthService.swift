import AppKit
import Foundation
import Network
import OSLog
import CryptoKit
import Security

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case callbackServerFailed
    case authorizationDenied(String)
    case tokenExchangeFailed(String)
    case noRefreshToken
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google Calendar credentials not configured"
        case .callbackServerFailed: "Failed to start OAuth callback server"
        case .authorizationDenied(let msg): "Authorization denied: \(msg)"
        case .tokenExchangeFailed(let msg): "Token exchange failed: \(msg)"
        case .noRefreshToken: "No refresh token available — please sign in again"
        case .keychainError(let status): "Keychain error: \(status)"
        }
    }
}

@MainActor
final class GoogleCalendarAuthService: ObservableObject {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "GoogleCalendarAuth")

    private static let callbackPort: UInt16 = 18923
    private static let redirectURI = "http://127.0.0.1:18923/callback"
    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let scope = "https://www.googleapis.com/auth/calendar.events.readonly"

    // Keychain service/account keys
    private static let keychainService = "com.incept5.NoteTaker.GoogleCalendar"
    private static let accessTokenAccount = "accessToken"
    private static let refreshTokenAccount = "refreshToken"
    private static let emailAccount = "email"
    private static let expiresAtAccount = "expiresAt"

    @Published var isSigningIn = false

    var isSignedIn: Bool {
        keychainRead(account: Self.refreshTokenAccount) != nil
    }

    var signedInEmail: String? {
        keychainRead(account: Self.emailAccount)
    }

    // MARK: - Sign In

    /// Full OAuth 2.0 + PKCE flow. Opens browser, waits for callback, exchanges code for tokens.
    func signIn() async throws -> String {
        guard GoogleCalendarConfig.isConfigured else { throw GoogleAuthError.notConfigured }

        isSigningIn = true
        defer { isSigningIn = false }

        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        let state = UUID().uuidString

        // Build authorization URL
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleCalendarConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
        ]

        let authorizationURL = components.url!

        // Start local callback server and open browser
        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            Task.detached {
                do {
                    let receivedCode = try await LocalOAuthCallbackServer.waitForCallback(
                        port: Self.callbackPort,
                        expectedState: state
                    )
                    continuation.resume(returning: receivedCode)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Small delay to ensure server is listening before opening browser
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                NSWorkspace.shared.open(authorizationURL)
            }
        }

        logger.info("Received OAuth callback code")

        // Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(
            code: code,
            codeVerifier: codeVerifier
        )

        // Store tokens in Keychain
        keychainWrite(account: Self.accessTokenAccount, value: tokens.accessToken)
        keychainWrite(account: Self.refreshTokenAccount, value: tokens.refreshToken)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        keychainWrite(account: Self.expiresAtAccount, value: ISO8601DateFormatter().string(from: expiresAt))

        // Fetch user email
        let email = try await fetchUserEmail(accessToken: tokens.accessToken)
        keychainWrite(account: Self.emailAccount, value: email)

        logger.info("Google Calendar sign-in complete for \(email, privacy: .public)")
        return email
    }

    // MARK: - Sign Out

    func signOut() {
        keychainDelete(account: Self.accessTokenAccount)
        keychainDelete(account: Self.refreshTokenAccount)
        keychainDelete(account: Self.emailAccount)
        keychainDelete(account: Self.expiresAtAccount)
        logger.info("Google Calendar signed out")
    }

    // MARK: - Access Token

    /// Returns a valid access token, refreshing if needed.
    func validAccessToken() async throws -> String {
        guard let refreshToken = keychainRead(account: Self.refreshTokenAccount) else {
            throw GoogleAuthError.noRefreshToken
        }

        // Check if current access token is still valid (with 60s buffer)
        if let accessToken = keychainRead(account: Self.accessTokenAccount),
           let expiresAtStr = keychainRead(account: Self.expiresAtAccount),
           let expiresAt = ISO8601DateFormatter().date(from: expiresAtStr),
           expiresAt.timeIntervalSinceNow > 60 {
            return accessToken
        }

        // Refresh the token
        logger.info("Refreshing Google access token")
        let tokens = try await refreshAccessToken(refreshToken: refreshToken)

        keychainWrite(account: Self.accessTokenAccount, value: tokens.accessToken)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        keychainWrite(account: Self.expiresAtAccount, value: ISO8601DateFormatter().string(from: expiresAt))

        if let newRefresh = tokens.refreshTokenIfPresent {
            keychainWrite(account: Self.refreshTokenAccount, value: newRefresh)
        }

        return tokens.accessToken
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Token Exchange

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    private struct RefreshTokenResponse {
        let accessToken: String
        let expiresIn: Int
        let refreshTokenIfPresent: String?
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": GoogleCalendarConfig.clientId,
            "client_secret": GoogleCalendarConfig.clientSecret,
            "redirect_uri": Self.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleAuthError.tokenExchangeFailed(errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw GoogleAuthError.tokenExchangeFailed("Invalid token response")
        }

        return TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> RefreshTokenResponse {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refreshToken,
            "client_id": GoogleCalendarConfig.clientId,
            "client_secret": GoogleCalendarConfig.clientSecret,
            "grant_type": "refresh_token",
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            // If refresh fails, sign out so user can re-auth
            signOut()
            throw GoogleAuthError.tokenExchangeFailed(errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw GoogleAuthError.tokenExchangeFailed("Invalid refresh response")
        }

        return RefreshTokenResponse(
            accessToken: accessToken,
            expiresIn: expiresIn,
            refreshTokenIfPresent: json["refresh_token"] as? String
        )
    }

    // MARK: - User Info

    private func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return "Unknown"
        }
        return email
    }

    // MARK: - Keychain Helpers

    private func keychainWrite(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.warning("Keychain write failed for \(account): \(status)")
        }
    }

    private func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Local OAuth Callback Server

private final class LocalOAuthCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let expectedState: String
    private let continuation: CheckedContinuation<String, Error>
    private var handled = false
    /// Strong self-reference to prevent deallocation while waiting for the callback.
    private var retainedSelf: LocalOAuthCallbackServer?

    static func waitForCallback(port: UInt16, expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let params = NWParameters.tcp
                let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
                let server = LocalOAuthCallbackServer(
                    listener: listener,
                    expectedState: expectedState,
                    continuation: continuation
                )
                server.retainedSelf = server
                server.start()
            } catch {
                continuation.resume(throwing: GoogleAuthError.callbackServerFailed)
            }
        }
    }

    private init(listener: NWListener, expectedState: String, continuation: CheckedContinuation<String, Error>) {
        self.listener = listener
        self.expectedState = expectedState
        self.continuation = continuation
    }

    private func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.finish(with: .failure(GoogleAuthError.callbackServerFailed))
            }
        }
        listener.start(queue: .global(qos: .userInitiated))

        // Timeout after 120 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.finish(with: .failure(GoogleAuthError.authorizationDenied("Timeout waiting for authorization")))
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }

            // Parse the HTTP request line to extract query parameters
            guard let firstLine = request.components(separatedBy: "\r\n").first,
                  let urlString = firstLine.components(separatedBy: " ").dropFirst().first,
                  let components = URLComponents(string: urlString) else {
                self.sendResponse(connection: connection, body: "Invalid request")
                return
            }

            let queryItems = components.queryItems ?? []

            // Check for error
            if let error = queryItems.first(where: { $0.name == "error" })?.value {
                self.sendResponse(connection: connection, body: "Authorization failed: \(error)")
                self.finish(with: .failure(GoogleAuthError.authorizationDenied(error)))
                return
            }

            // Validate state
            guard let state = queryItems.first(where: { $0.name == "state" })?.value,
                  state == self.expectedState else {
                self.sendResponse(connection: connection, body: "Invalid state parameter")
                return
            }

            // Extract code
            guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
                self.sendResponse(connection: connection, body: "No authorization code received")
                return
            }

            self.sendResponse(connection: connection, body: """
                <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px;">
                <h2>Authorization successful</h2>
                <p>You can close this tab and return to NoteTaker.</p>
                </body></html>
                """)

            self.finish(with: .success(code))
        }
    }

    private func sendResponse(connection: NWConnection, body: String) {
        let isHTML = body.hasPrefix("<")
        let contentType = isHTML ? "text/html" : "text/plain"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(with result: Result<String, Error>) {
        guard !handled else { return }
        handled = true
        retainedSelf = nil
        listener.cancel()
        switch result {
        case .success(let code): continuation.resume(returning: code)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

// MARK: - Base64URL Encoding

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
