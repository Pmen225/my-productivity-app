#if os(iOS) || os(macOS)
import AuthenticationServices
import CryptoKit
import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// What can go wrong signing in to Google. Every case already carries a safe,
/// fixed sentence — nothing here is built from a token, a code, or raw server
/// text, so there is never anything to redact before it reaches a case here.
public enum GoogleOAuthError: Error, Equatable {
    case missingClientID
    case invalidRedirectURI
    case userCancelled
    case authorisationFailed
    case tokenExchangeFailed
    case noRefreshToken
    case network
}

/// One Google account's OAuth state: authorisation-code + PKCE, no client
/// secret, matching the flow Google issues for public "installed app" clients.
///
/// The refresh token is the only long-lived credential and it never leaves the
/// Keychain (`KeychainService`); the access token lives in memory for this
/// process only and is refreshed automatically shortly before it expires.
@MainActor
public final class GoogleOAuth: NSObject {
    private struct AccessToken {
        let value: String
        let expiresAt: Date
    }

    static let keychainAccount = "google.calendar.refreshToken"

    static let scopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/calendar.readonly",
        "email",
    ]

    private var accessToken: AccessToken?
    private var webAuthSession: ASWebAuthenticationSession?
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        super.init()
    }

    public var isSignedIn: Bool { KeychainService.hasKey(account: Self.keychainAccount) }

    /// Runs the interactive sign-in, exchanges the code for tokens, and stores
    /// the refresh token. Returns the account email for `connection.accountLabel`.
    public func signIn(clientID: String) async throws -> String {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else { throw GoogleOAuthError.missingClientID }
        guard let redirectURI = Self.redirectURI(clientID: trimmedClientID) else {
            throw GoogleOAuthError.invalidRedirectURI
        }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let authURL = components?.url, let callbackScheme = redirectURI.scheme else {
            throw GoogleOAuthError.authorisationFailed
        }

        let callbackURL = try await authenticate(url: authURL, callbackURLScheme: callbackScheme)
        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw GoogleOAuthError.authorisationFailed }

        let tokens = try await exchangeCode(
            code,
            verifier: verifier,
            clientID: trimmedClientID,
            redirectURI: redirectURI
        )
        guard let refreshToken = tokens.refreshToken else { throw GoogleOAuthError.noRefreshToken }
        KeychainService.set(refreshToken, account: Self.keychainAccount)
        accessToken = AccessToken(value: tokens.accessToken, expiresAt: Date().addingTimeInterval(tokens.expiresIn))

        return try await fetchEmail(accessToken: tokens.accessToken)
    }

    /// Deletes the Keychain entry and clears memory. Never throws — signing out
    /// must always be possible, including from a broken state.
    public func signOut() {
        KeychainService.delete(account: Self.keychainAccount)
        accessToken = nil
        webAuthSession = nil
    }

    /// A valid access token, refreshing first when within 60 seconds of expiry.
    public func validAccessToken(clientID: String) async throws -> String {
        if let accessToken, accessToken.expiresAt.timeIntervalSinceNow > 60 {
            return accessToken.value
        }
        guard let refreshToken = KeychainService.get(account: Self.keychainAccount) else {
            throw GoogleOAuthError.noRefreshToken
        }
        let refreshed = try await refresh(refreshToken: refreshToken, clientID: clientID)
        let token = AccessToken(
            value: refreshed.accessToken,
            expiresAt: Date().addingTimeInterval(refreshed.expiresIn)
        )
        accessToken = token
        return token.value
    }

    // MARK: - PKCE

    /// A cryptographically random verifier, base64url-encoded with no padding.
    ///
    /// `nonisolated`: this touches no actor state — it is a pure function the
    /// tests (and `signIn`) call without needing the main actor.
    nonisolated static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    /// The S256 challenge for a verifier: base64url(SHA256(verifier)), no padding.
    nonisolated static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    nonisolated private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Google's installed-app redirect convention: the reversed client id as a
    /// custom URL scheme. Derived from the client id itself — nothing here
    /// hard-codes a particular Google Cloud project.
    nonisolated static func redirectURI(clientID: String) -> URL? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let projectID = String(clientID.dropLast(suffix.count))
        guard !projectID.isEmpty else { return nil }
        return URL(string: "com.googleusercontent.apps.\(projectID):/oauth2redirect")
    }

    // MARK: - Network

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private struct UserInfoResponse: Decodable {
        let email: String?
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        clientID: String,
        redirectURI: URL
    ) async throws -> TokenResponse {
        try await postForm(
            to: "https://oauth2.googleapis.com/token",
            params: [
                "code": code,
                "client_id": clientID,
                "redirect_uri": redirectURI.absoluteString,
                "grant_type": "authorization_code",
                "code_verifier": verifier,
            ],
            failure: .tokenExchangeFailed
        )
    }

    private func refresh(refreshToken: String, clientID: String) async throws -> TokenResponse {
        try await postForm(
            to: "https://oauth2.googleapis.com/token",
            params: [
                "refresh_token": refreshToken,
                "client_id": clientID,
                "grant_type": "refresh_token",
            ],
            failure: .tokenExchangeFailed
        )
    }

    private func postForm(
        to urlString: String,
        params: [String: String],
        failure: GoogleOAuthError
    ) async throws -> TokenResponse {
        guard let url = URL(string: urlString) else { throw failure }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw GoogleOAuthError.network
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw failure
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw failure
        }
        return decoded
    }

    private func fetchEmail(accessToken: String) async throws -> String {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else {
            throw GoogleOAuthError.authorisationFailed
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw GoogleOAuthError.network
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let info = try? JSONDecoder().decode(UserInfoResponse.self, from: data),
              let email = info.email
        else { throw GoogleOAuthError.authorisationFailed }
        return email
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return (components.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()
    }

    // MARK: - ASWebAuthenticationSession

    private func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleOAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: GoogleOAuthError.authorisationFailed)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleOAuthError.authorisationFailed)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webAuthSession = session
            if !session.start() {
                continuation.resume(throwing: GoogleOAuthError.authorisationFailed)
            }
        }
    }
}

extension GoogleOAuth: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let anchor = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return anchor ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
#endif
