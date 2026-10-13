import Foundation
import Testing

@testable import Mitori

// Ported from ApplePackage Tests/ApplePackageTests/CookieTests.swift at 3b535f1.
struct AppleStoreCookieTests {
    @Test
    func buildCookieHeaderMatchesLeadingDotDomain() throws {
        let endpoint = try #require(URL(string: "https://p45-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"))
        let cookies = [
            Cookie(
                name: "mz_at0",
                value: "session",
                path: "/",
                domain: ".itunes.apple.com",
                expiresAt: Date().addingTimeInterval(60).timeIntervalSince1970,
                httpOnly: true,
                secure: true
            ),
        ]

        let headers = cookies.buildCookieHeader(endpoint)
        #expect(headers.count == 1)
        #expect(headers.first?.0 == "Cookie")
        #expect(headers.first?.1 == "mz_at0=session")
    }

    @Test
    func mergeCookiesKeepsSameNameAcrossDomainsAndPaths() throws {
        var cookies: [Cookie] = []
        let url = try #require(URL(string: "https://buy.itunes.apple.com/"))
        cookies.mergeCookies([
            "X-Dsid=apple; Domain=.apple.com; Path=/",
            "X-Dsid=volume; Domain=.volume.itunes.apple.com; Path=/",
            "X-Dsid=webobjects; Domain=.apple.com; Path=/WebObjects",
        ].flatMap { HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": $0], for: url) })

        #expect(cookies.count == 3)
        #expect(Set(cookies.map(\.value)) == ["apple", "volume", "webobjects"])
    }
}
