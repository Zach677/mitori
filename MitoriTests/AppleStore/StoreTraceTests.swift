import Foundation
import Testing

@testable import Mitori

/// The trace must carry only safe fields; every secret-bearing field is fed a sentinel (I-8).
struct StoreTraceTests {
    @Test
    func traceLineHoldsSafeFieldsAndNoSentinel() throws {
        let body = try PropertyListSerialization.data(
            fromPropertyList: ["appleId": "SENTINEL-APPLEID", "password": "SENTINEL-PASSWORD", "guid": "SENTINEL-GUID"],
            format: .xml,
            options: 0
        )
        let url = try #require(URL(
            string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/SENTINEL-PATH?guid=SENTINEL-QUERY"
        ))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("mz_at0=SENTINEL-COOKIE; itspod=SENTINEL-POD", forHTTPHeaderField: "Cookie")
        request.setValue("Bearer SENTINEL-AUTH", forHTTPHeaderField: "Authorization")
        request.setValue("SENTINEL-TOKEN", forHTTPHeaderField: "X-Token")
        request.setValue("SENTINEL-DSID", forHTTPHeaderField: "X-Dsid")
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Set-Cookie": "session=SENTINEL-SETCOOKIE; Domain=.apple.com; Path=/",
                "Location": "https://sentinel-host.example/next?guid=SENTINEL-LOCATION",
                "pod": "SENTINEL-PODHEADER",
                "x-apple-token": "SENTINEL-RESPONSE-TOKEN",
            ]
        ))
        let responseBody = try PropertyListSerialization.data(
            fromPropertyList: ["passwordToken": "SENTINEL-PASSWORDTOKEN", "dsPersonId": "SENTINEL-DSPERSONID"],
            format: .xml,
            options: 0
        )

        let line = StoreTrace.describe(
            request: request,
            response: response,
            data: responseBody,
            error: nil,
            operation: "login",
            attempt: 2
        )

        #expect(!line.lowercased().contains("sentinel"), "\(line)")
        for field in [
            "op=login", "endpoint=auth.legacy", "attempt=2", "method=POST", "cookiesSent=2",
            "status=302", "cookiesSet=1", "headers=[location,pod,set-cookie,x-apple-token]",
            "body=\(responseBody.count)B", "type=plist",
        ] {
            #expect(line.contains(field), "missing \(field) in \(line)")
        }
    }

    @Test
    func transportErrorLineHoldsOnlyTheCode() throws {
        let url = try #require(URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=SENTINEL-QUERY"))
        let error = URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: url])

        let line = StoreTrace.describe(
            request: URLRequest(url: url),
            response: nil,
            data: nil,
            error: error,
            operation: "reauth",
            attempt: 1
        )

        #expect(line == "op=reauth endpoint=auth.native attempt=1 method=GET cookiesSent=0 error=URLError(-1001)")
    }

    @Test(arguments: [
        ("https://init.itunes.apple.com/bag.xml?guid=X", "bag"),
        ("https://auth.itunes.apple.com/auth/v1/native/fast/", "auth.native"),
        ("https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate", "auth.legacy"),
        ("https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=X", "probe"),
        ("https://itunes.apple.com/lookup?bundleId=X", "lookup"),
        ("https://itunes.apple.com/search?term=X", "search"),
        ("https://example.com/authenticate", "other"),
    ])
    func endpointLabels(url: String, label: String) {
        #expect(StoreTrace.endpointLabel(for: URL(string: url)) == label)
    }

    @Test
    func attemptsCountPerEndpointWithinOneOperation() {
        let operation = StoreTrace.Operation("login")

        #expect(operation.nextAttempt(for: "auth.native") == 1)
        #expect(operation.nextAttempt(for: "bag") == 1)
        #expect(operation.nextAttempt(for: "auth.native") == 2)
    }

    @Test
    func innerOperationKeepsTheOuterName() async {
        let name = await StoreTrace.run("refresh.manual") {
            await StoreTrace.run("reauth") { StoreTrace.operation?.name }
        }

        #expect(name == "refresh.manual")
    }
}
