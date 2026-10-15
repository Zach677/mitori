//
//  Authenticate.swift
//  ApplePackage
//
//  Created by QAQ on 2023/10/4.
//

import Foundation

public struct AuthenticationResult: Sendable {
    public var account: Account
    public var responsePlist: Data

    public init(account: Account, responsePlist: Data) {
        self.account = account
        self.responsePlist = responsePlist
    }
}

public enum Authenticator {
    private enum LoginResponse {
        case success(AuthenticationResult)
        case codeRequired
        case redirect(URL)
        case retryWithoutCookies
        case failure(String)
    }

    enum RedirectHandling: Equatable {
        case follow(URL)
        case parseBody
        case retryWithoutCookies
    }

    private static let maxTransientRequestAttempts = 3
    // Each retry resends the password; pace it like ipatool (B14).
    private static let transientRetryDelayNanoseconds: UInt64 = 10_000_000_000
    private static let maxTransientRetryDelayNanoseconds: UInt64 = 30_000_000_000

    public static func authenticate(
        email: String,
        password: String,
        code: String = "",
        cookies: [Cookie] = [],
        deviceIdentifier: String = Configuration.deviceIdentifier
    ) async throws -> Account {
        try await authenticateWithResponse(
            email: email,
            password: password,
            code: code,
            cookies: cookies,
            deviceIdentifier: deviceIdentifier
        ).account
    }

    static func authenticateWithResponse(
        email: String,
        password: String,
        code: String = "",
        cookies: [Cookie] = [],
        deviceIdentifier: String = Configuration.deviceIdentifier,
        transport: any StoreTransport = URLSessionStoreTransport.shared,
        signAction: (Data) throws -> String = AppleActionSigner.sign
    ) async throws -> AuthenticationResult {
        let bagOutput = try await Bag.fetchBag(deviceIdentifier: deviceIdentifier, transport: transport)

        var requestEndpoint: URL = try createInitialRequestEndpoint(baseURL: bagOutput.authEndpoint, deviceIdentifier: deviceIdentifier)
        var cookies: [Cookie] = cookies
        var storeFront = ""
        var pod: String?
        var redirectAttempt = 0
        var lastStatus = 0
        var didClearCookies = false
        let requestData = try makeRequestData(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier
        )

        while redirectAttempt <= 3 {
            let response = try await sendAuthenticationRequest {
                let request = try makeRequest(
                    endpoint: requestEndpoint,
                    data: requestData,
                    cookies: cookies,
                    signAction: signAction
                )
                let response = try await transport.data(for: request)
                return (response, UInt(response.1.statusCode), response.1.value(forHTTPHeaderField: "Retry-After"))
            }
            lastStatus = response.1.statusCode
            let result = try parseResponse(
                data: response.0,
                response: response.1,
                currentURL: requestEndpoint,
                email: email,
                password: password,
                code: code,
                cookies: &cookies,
                storeFront: &storeFront,
                pod: &pod
            )
            switch result {
            case let .success(authenticationResult):
                return authenticationResult
            case let .redirect(url):
                // The login POST carries credentials, so validate before following (I-2).
                requestEndpoint = try StoreRedirectPolicy.validated(url)
                redirectAttempt += 1
            case .retryWithoutCookies:
                guard !didClearCookies else {
                    throw StoreAuthError.redirectExhausted(status: lastStatus)
                }
                cookies = []
                didClearCookies = true
            case .codeRequired:
                throw StoreAuthError.codeRequired
            case let .failure(message):
                throw StoreAuthError.badLogin(message: message)
            }
        }

        throw StoreAuthError.redirectExhausted(status: lastStatus)
    }

    static func sendAuthenticationRequest<Response>(
        execute: () async throws -> (response: Response, statusCode: UInt, retryAfter: String?),
        sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async throws -> Response {
        for attempt in 1 ... maxTransientRequestAttempts {
            let result = try await execute()
            guard isTransientAuthenticationStatus(result.statusCode),
                  attempt < maxTransientRequestAttempts
            else {
                return result.response
            }
            var delay = min(transientRetryDelayNanoseconds << (attempt - 1), maxTransientRetryDelayNanoseconds)
            // shortcut: only the delta-seconds form of Retry-After is read; an HTTP date falls back to the backoff.
            if let retryAfter = result.retryAfter.flatMap({ UInt64($0.trimmingCharacters(in: .whitespaces)) }) {
                guard retryAfter <= maxTransientRetryDelayNanoseconds / 1_000_000_000 else {
                    return result.response
                }
                delay = max(retryAfter, 1) * 1_000_000_000
            }
            try await sleep(delay)
        }
        preconditionFailure("authentication retry loop must return")
    }

    private static func isTransientAuthenticationStatus(_ statusCode: UInt) -> Bool {
        statusCode == 204 || statusCode == 404 || statusCode == 429 || statusCode / 100 == 5
    }

    public static func rotatePasswordToken(for account: inout Account) async throws {
        let newAccount = try await authenticate(
            email: account.email,
            password: account.password,
            code: "",
            cookies: account.cookie
        )
        account = newAccount
    }

    private static func createInitialRequestEndpoint(
        baseURL: URL,
        deviceIdentifier: String
    ) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            try ensureFailed("\(Strings.invalidAuthEndpoint): \(baseURL)")
        }
        comps.queryItems = [
            URLQueryItem(name: "guid", value: deviceIdentifier),
        ]
        let url = try comps.url.get()
        return try StoreRedirectPolicy.validated(Bag.normalizedAuthEndpoint(from: url.absoluteString) ?? url)
    }

    /// Apple's native auth host 301s `/fast` (no trailing slash) to an HTML page
    /// with no Location header. Recover by adding the slash, and trim/resolve
    /// any Location we do receive against the current request URL.
    static func resolvedRedirectURL(locationHeader: String?, currentURL: URL) -> URL? {
        if let raw = locationHeader?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let parsed = URL(string: raw, relativeTo: currentURL)?.absoluteURL ?? URL(string: raw)
            if let parsed {
                // Rewrite only trusted URLs, so the caller's check still sees a rejected Location.
                guard (try? StoreRedirectPolicy.validated(parsed)) != nil else { return parsed }
                return Bag.normalizedAuthEndpoint(from: parsed.absoluteString) ?? parsed
            }
        }

        guard let normalized = Bag.normalizedAuthEndpoint(from: currentURL.absoluteString),
              normalized.absoluteString != currentURL.absoluteString
        else {
            return nil
        }
        return normalized
    }

    /// Cookie-backed reauth often 302s with no Location. Follow Location when we
    /// have one; otherwise parse a plist body or retry once without cookies.
    static func redirectHandling(
        status: Int,
        locationHeader: String?,
        currentURL: URL,
        bodyLength: Int
    ) -> RedirectHandling? {
        guard [301, 302, 303, 307, 308].contains(status) else { return nil }
        if let url = resolvedRedirectURL(locationHeader: locationHeader, currentURL: currentURL) {
            return .follow(url)
        }
        if bodyLength > 0 {
            return .parseBody
        }
        return .retryWithoutCookies
    }

    static func locationCandidate(from response: HTTPURLResponse) -> String? {
        for name in ["location", "x-apple-orig-url"] {
            if let value = response.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                return value
            }
        }
        return nil
    }

    static func makeRequest(
        endpoint: URL,
        email: String,
        password: String,
        code: String,
        cookies: [Cookie],
        deviceIdentifier: String,
        signAction: (Data) throws -> String = AppleActionSigner.sign
    ) throws -> URLRequest {
        let data = try makeRequestData(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier
        )
        return try makeRequest(
            endpoint: endpoint,
            data: data,
            cookies: cookies,
            signAction: signAction
        )
    }

    private static func makeRequestData(
        email: String,
        password: String,
        code: String,
        deviceIdentifier: String
    ) throws -> Data {
        let parameters: [String: String] = [
            "appleId": email,
            "attempt": "\(code.isEmpty ? "4" : "2")",
            "guid": deviceIdentifier,
            "password": "\(password)\(code)",
            "rmp": "0",
            "why": "signIn",
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: parameters,
            format: .xml,
            options: 0
        )
    }

    private static func makeRequest(
        endpoint: URL,
        data: Data,
        cookies: [Cookie],
        signAction: (Data) throws -> String
    ) throws -> URLRequest {
        var headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Content-Type", "application/x-apple-plist"),
        ]
        for item in cookies.buildCookieHeader(endpoint) {
            headers.append(item)
        }
        let actionSignature = try signAction(data)
        APLogger.logRequest(method: "POST", url: endpoint.absoluteString, headers: headers)
        headers.append(("X-Apple-ActionSignature", actionSignature))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private static func parseResponse(
        data: Data,
        response: HTTPURLResponse,
        currentURL: URL,
        email: String,
        password: String,
        code: String,
        cookies: inout [Cookie],
        storeFront: inout String,
        pod: inout String?
    ) throws -> LoginResponse {
        APLogger.logResponse(
            status: UInt(response.statusCode),
            headers: response.allHeaderFields.map { ("\($0.key)", "\($0.value)") },
            bodySize: data.count
        )

        cookies.mergeCookies(response.setCookies())

        if let storeFrontValue = response.value(forHTTPHeaderField: "x-set-apple-store-front")?
            .components(separatedBy: "-").first,
            !storeFrontValue.isEmpty
        {
            storeFront = storeFrontValue
        }

        if let podValue = response.value(forHTTPHeaderField: "pod"), !podValue.isEmpty {
            pod = podValue
            APLogger.info("auth: received pod value: \(podValue)")
        }

        if let handling = redirectHandling(
            status: response.statusCode,
            locationHeader: locationCandidate(from: response),
            currentURL: currentURL,
            bodyLength: data.count
        ) {
            switch handling {
            case let .follow(url):
                return .redirect(url)
            case .retryWithoutCookies:
                return .retryWithoutCookies
            case .parseBody:
                break
            }
        }

        guard !data.isEmpty else {
            throw StoreAuthError.malformedResponse("\(Strings.responseBodyEmpty) (HTTP \(response.statusCode))")
        }

        let listItem: Any
        do {
            listItem = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            if redirectHandling(
                status: response.statusCode,
                locationHeader: nil,
                currentURL: currentURL,
                bodyLength: 0
            ) != nil
            {
                return .retryWithoutCookies
            }
            throw StoreAuthError.malformedResponse("response is not a property list (HTTP \(response.statusCode))")
        }
        guard let dic = listItem as? [String: Any] else {
            throw StoreAuthError.malformedResponse(Strings.responseNotDictionary)
        }

        if let failureType = dic["failureType"] as? String,
           failureType.isEmpty,
           code.isEmpty,
           let customerMessage = dic["customerMessage"] as? String,
           customerMessage == "MZFinance.BadLogin.Configurator_message"
        {
            return .codeRequired
        }

        if let failureType = dic["failureType"] as? String, failureType == "5005" {
            throw StoreAuthError.invalid2FACode
        }

        let failureMessage = (dic["dialog"] as? [String: Any])?["explanation"] as? String ?? (dic["customerMessage"] as? String)
        guard let accountInfoDic = dic["accountInfo"] as? [String: Any] else {
            if let failureMessage { return .failure(failureMessage) }
            throw StoreAuthError.malformedResponse(Strings.missingAccountInfo)
        }
        guard let addressInfoDic = accountInfoDic["address"] as? [String: Any] else {
            if let failureMessage { return .failure(failureMessage) }
            throw StoreAuthError.malformedResponse(Strings.missingAddress)
        }
        guard !storeFront.isEmpty else {
            throw StoreAuthError.malformedResponse("missing x-set-apple-store-front header")
        }
        guard Configuration.countryCode(for: storeFront) != nil else {
            throw StoreAuthError.unsupportedStorefront(storeFront)
        }

        let account: Account
        do {
            account = try Account(
                email: email,
                password: password,
                appleId: accountInfoDic["appleId"] as? String,
                store: storeFront,
                firstName: addressInfoDic["firstName"] as? String,
                lastName: addressInfoDic["lastName"] as? String,
                passwordToken: dic["passwordToken"] as? String,
                directoryServicesIdentifier: dic["dsPersonId"] as? String,
                cookie: cookies,
                pod: pod
            )
        } catch {
            throw StoreAuthError.malformedResponse(error.localizedDescription)
        }
        return .success(AuthenticationResult(account: account, responsePlist: data))
    }
}
