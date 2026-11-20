import Foundation

protocol BalanceRefreshing: Sendable {
    func refreshBalance(for meta: StoredAccountMeta, secret: StoredAccountSecret) async throws -> BalanceResult
}

actor BalanceService: BalanceRefreshing {
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
            account: secret.restoredAccount(meta: meta),
            probeBundleID: probeBundleID,
            probeAdamID: meta.probeAdamID,
            deviceIdentifier: meta.deviceIdentifier
        )
        let snapshot = try BalanceParser.parse(plistData: probeResult.payload, source: .probe)
        return BalanceResult(
            snapshot: snapshot,
            account: probeResult.account,
            probeAdamID: probeResult.probeAdamID
        )
    }
}

struct BalanceResult: Sendable {
    var snapshot: BalanceSnapshot
    var account: Account
    var probeAdamID: Int64? = nil
}

struct ProbePayloadResult: Sendable {
    var payload: Data
    var account: Account
    var probeAdamID: Int64
}

actor BalanceProbeClient {
    private let maxRedirectCount = 3
    private let transport: any StoreTransport

    init(transport: any StoreTransport = URLSessionStoreTransport.shared) {
        self.transport = transport
    }

    func fetchProbePayload(
        account: Account,
        probeBundleID: String,
        probeAdamID: Int64? = nil,
        deviceIdentifier: String
    ) async throws -> ProbePayloadResult {
        guard let countryCode = Configuration.countryCode(for: account.store) else {
            throw StoreAuthError.unsupportedStorefront(account.store)
        }

        if let cachedAdamID = probeAdamID {
            do {
                return try await performProbe(
                    account: account,
                    adamID: cachedAdamID,
                    deviceIdentifier: deviceIdentifier
                )
            } catch StoreAuthError.probeAppNotOwned {
                // Re-resolve the bundle ID once in case the cached Adam ID is stale.
                let lookedUp = try await Lookup.lookup(
                    bundleID: probeBundleID,
                    countryCode: countryCode,
                    transport: transport
                )
                guard lookedUp.id != cachedAdamID else {
                    throw StoreAuthError.probeAppNotOwned
                }
                return try await performProbe(
                    account: account,
                    adamID: lookedUp.id,
                    deviceIdentifier: deviceIdentifier
                )
            }
        }

        let app = try await Lookup.lookup(bundleID: probeBundleID, countryCode: countryCode, transport: transport)
        return try await performProbe(
            account: account,
            adamID: app.id,
            deviceIdentifier: deviceIdentifier
        )
    }

    private func performProbe(
        account: Account,
        adamID: Int64,
        deviceIdentifier: String
    ) async throws -> ProbePayloadResult {
        var account = account
        var url = try makeProbeURL(pod: account.pod, guid: deviceIdentifier)
        let requestBody = try makeRequestBody(deviceIdentifier: deviceIdentifier, adamID: adamID)

        var redirectCount = 0
        while true {
            let request = makeRequest(url: url, body: requestBody, account: account)
            let (data, response) = try await transport.data(for: request)

            updateAccount(&account, from: response)

            if isRedirect(response.statusCode) {
                guard redirectCount < maxRedirectCount else {
                    throw StoreAuthError.redirectExhausted(status: response.statusCode)
                }
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      !location.isEmpty else {
                    throw StoreAuthError.malformedResponse("redirect without a Location header (HTTP \(response.statusCode))")
                }
                url = try StoreRedirectPolicy.validatedURL(location: location, relativeTo: url)
                redirectCount += 1
                continue
            }

            if let knownFailure = parseKnownFailure(from: data, statusCode: response.statusCode) {
                throw knownFailure
            }

            guard (200 ..< 300).contains(response.statusCode) else {
                throw StoreAuthError.transport(URLError(
                    .badServerResponse,
                    userInfo: [NSLocalizedDescriptionKey: "Apple returned HTTP \(response.statusCode)."]
                ))
            }

            return ProbePayloadResult(payload: data, account: account, probeAdamID: adamID)
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
        guard StoreRedirectPolicy.isTrustedHost(url.host) else {
            throw StoreAuthError.malformedResponse("invalid store host from pod \(pod ?? "nil")")
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
        account.cookie.mergeCookies(response.setCookies())

        if let pod = StoreResponseHeaders.pod(from: response) {
            account.pod = pod
        }

        if let storefront = StoreResponseHeaders.storefront(from: response),
           Configuration.countryCode(for: storefront) != nil
        {
            account.store = storefront
        }
    }

    private func parseKnownFailure(from data: Data, statusCode: Int) -> Error? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        let failureType = StoreResponseHeaders.failureType(in: dictionary)
        let customerMessage = dictionary["customerMessage"] as? String

        switch failureType {
        case "2034", "2042":
            return StoreAuthError.sessionExpired
        case "9610":
            return StoreAuthError.probeAppNotOwned
        default:
            break
        }

        // Unknown failures stay visible, but their text never selects a state (I-3).
        // A server error keeps its network backoff even when it carries a message (§3).
        if (200 ..< 300).contains(statusCode), let customerMessage, !customerMessage.isEmpty {
            return MitoriError.unknown(customerMessage)
        }

        return nil
    }
}
