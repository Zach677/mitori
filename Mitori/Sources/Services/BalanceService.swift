import ApplePackage
import Foundation

actor BalanceService {
    private let probeClient: BalanceProbeClient

    init(probeClient: BalanceProbeClient = BalanceProbeClient()) {
        self.probeClient = probeClient
    }

    func refreshBalance(for meta: StoredAccountMeta, secret: StoredAccountSecret) async throws -> BalanceResult {
        let probeBundleID = meta.probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probeBundleID.isEmpty else {
            throw MitoriError.missingProbeBundleID
        }

        let probeResult = try await probeClient.fetchProbePayload(
            account: secret.restoredAccount(),
            probeBundleID: probeBundleID,
            deviceIdentifier: meta.deviceIdentifier
        )
        let snapshot = try BalanceParser.parse(plistData: probeResult.payload, source: .probe)
        return BalanceResult(snapshot: snapshot, secret: StoredAccountSecret(account: probeResult.account))
    }
}

struct ProbePayloadResult: Sendable {
    var payload: Data
    var account: Account
}

final class BalanceProbeClient {
    func fetchProbePayload(
        account: Account,
        probeBundleID: String,
        deviceIdentifier: String
    ) async throws -> ProbePayloadResult {
        var account = account
        Configuration.deviceIdentifier = deviceIdentifier

        guard let countryCode = Configuration.countryCode(for: account.store) else {
            throw MitoriError.unsupportedStorefront(account.store)
        }

        let app = try await Lookup.lookup(bundleID: probeBundleID, countryCode: countryCode)
        let url = try makeProbeURL(pod: account.pod, guid: deviceIdentifier)
        let requestBody = try makeRequestBody(deviceIdentifier: deviceIdentifier, adamID: app.id)

        let cookieStorage = HTTPCookieStorage()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = cookieStorage

        let foundationCookies = account.cookie.compactMap(\.foundationCookie)
        if !foundationCookies.isEmpty {
            cookieStorage.setCookies(foundationCookies, for: url, mainDocumentURL: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.httpShouldHandleCookies = true
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")

        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MitoriError.unknown("Unexpected response type from Apple.")
        }

        if let pod = response.value(forHTTPHeaderField: "pod"), !pod.isEmpty {
            account.pod = pod
        }

        if let storefront = response.value(forHTTPHeaderField: "x-set-apple-store-front")?
            .split(separator: "-")
            .first
        {
            account.store = String(storefront)
        }

        if let cookies = cookieStorage.cookies, !cookies.isEmpty {
            account.cookie = account.cookie.merging(cookies.map(\.appleCookie))
        }

        if let knownFailure = parseKnownFailure(from: data) {
            throw knownFailure
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw MitoriError.network("Apple returned HTTP \(response.statusCode).")
        }

        return ProbePayloadResult(payload: data, account: account)
    }

    private func makeProbeURL(pod: String?, guid: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Configuration.storeAPIHost(pod: pod)
        components.path = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        components.queryItems = [URLQueryItem(name: "guid", value: guid)]
        guard let url = components.url else {
            throw MitoriError.unknown("Failed to build Apple balance probe URL.")
        }
        return url
    }

    private func makeRequestBody(deviceIdentifier: String, adamID: Int64) throws -> Data {
        let payload: [String: Any] = [
            "creditDisplay": "",
            "guid": deviceIdentifier,
            "salableAdamId": adamID,
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
    }

    private func parseKnownFailure(from data: Data) -> MitoriError? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        let failureType = dictionary["failureType"] as? String
        let customerMessage = dictionary["customerMessage"] as? String

        switch failureType {
        case "2034", "2042":
            return .sessionExpired
        case "9610":
            return .probeAppNotOwned
        default:
            break
        }

        if customerMessage == "Your password has changed." {
            return .sessionExpired
        }

        if let customerMessage, !customerMessage.isEmpty {
            return .unknown(customerMessage)
        }

        return nil
    }
}

private extension Cookie {
    var foundationCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .path: path,
            .domain: domain ?? "itunes.apple.com",
            .secure: secure,
        ]

        if let expiresAt {
            properties[.expires] = Date(timeIntervalSince1970: expiresAt)
        }

        if httpOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = true
        }

        return HTTPCookie(properties: properties)
    }
}

private extension HTTPCookie {
    var appleCookie: Cookie {
        Cookie(
            name: name,
            value: value,
            path: path,
            domain: domain,
            expiresAt: expiresDate?.timeIntervalSince1970,
            httpOnly: isHTTPOnly,
            secure: isSecure
        )
    }
}

private extension Array where Element == Cookie {
    func merging(_ incoming: [Cookie]) -> [Cookie] {
        var dictionary = Dictionary(uniqueKeysWithValues: map { ($0.name, $0) })
        for cookie in incoming {
            dictionary[cookie.name] = cookie
        }
        return Array(dictionary.values)
    }
}
