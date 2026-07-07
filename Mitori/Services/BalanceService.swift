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
    private let maxRedirectCount = 3

    func fetchProbePayload(
        account: Account,
        probeBundleID: String,
        deviceIdentifier: String
    ) async throws -> ProbePayloadResult {
        var account = account

        guard let countryCode = Configuration.countryCode(for: account.store) else {
            throw MitoriError.unsupportedStorefront(account.store)
        }

        let app = try await Lookup.lookup(bundleID: probeBundleID, countryCode: countryCode)
        var url = try makeProbeURL(pod: account.pod, guid: deviceIdentifier)
        let requestBody = try makeRequestBody(deviceIdentifier: deviceIdentifier, adamID: app.id)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false

        let redirectDelegate = BalanceProbeRedirectDelegate()
        let session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var redirectCount = 0
        while true {
            let request = makeRequest(url: url, body: requestBody, account: account)
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MitoriError.unknown("Unexpected response type from Apple.")
            }

            updateAccount(&account, from: response)

            if isRedirect(response.statusCode) {
                guard redirectCount < maxRedirectCount else {
                    throw MitoriError.network("Apple returned too many redirects.")
                }
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let redirectURL = URL(string: location, relativeTo: url)?.absoluteURL
                else {
                    throw MitoriError.network("Apple returned a redirect without a Location header.")
                }
                url = redirectURL
                redirectCount += 1
                continue
            }

            if let knownFailure = parseKnownFailure(from: data) {
                throw knownFailure
            }

            guard (200 ..< 300).contains(response.statusCode) else {
                throw MitoriError.network("Apple returned HTTP \(response.statusCode).")
            }

            return ProbePayloadResult(payload: data, account: account)
        }
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

    private func makeRequest(url: URL, body: Data, account: Account) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")
        for header in account.cookie.buildCookieHeader(url) {
            request.setValue(header.1, forHTTPHeaderField: header.0)
        }
        return request
    }

    private func isRedirect(_ statusCode: Int) -> Bool {
        (300 ..< 400).contains(statusCode)
    }

    private func updateAccount(
        _ account: inout Account,
        from response: HTTPURLResponse
    ) {
        if let pod = response.value(forHTTPHeaderField: "pod"), !pod.isEmpty {
            account.pod = pod
        }

        if let storefront = response.value(forHTTPHeaderField: "x-set-apple-store-front")?
            .split(separator: "-")
            .first
        {
            account.store = String(storefront)
        }
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

private final class BalanceProbeRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
