//
//  AppleStoreCookieTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/10/09.
//

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

    // Foundation gives a cookie that has no Domain attribute its host with no leading dot (#4).
    @Test
    func hostOnlyCookieGoesOnlyToItsExactHost() throws {
        let host = try #require(URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/"))
        let subdomain = try #require(URL(string: "https://sub.buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/"))
        var cookies: [Cookie] = []
        cookies.mergeCookies(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "session=host; Path=/"], for: host))

        #expect(cookies.buildCookieHeader(host).first?.1 == "session=host")
        #expect(cookies.buildCookieHeader(subdomain).isEmpty)
    }

    @Test
    func mergeCookiesKeepsHostOnlyAndDomainCookieOfTheSameHost() throws {
        let url = try #require(URL(string: "https://buy.itunes.apple.com/"))
        var cookies: [Cookie] = []
        cookies.mergeCookies([
            "session=host; Path=/",
            "session=domain; Domain=buy.itunes.apple.com; Path=/",
        ].flatMap { HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": $0], for: url) })

        #expect(Set(cookies.map(\.value)) == ["host", "domain"])
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

    @Test
    func secureCookieMatchesUppercaseHTTPSScheme() throws {
        let endpoint = try #require(URL(string: "HTTPS://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/"))
        let cookies = [
            Cookie(
                name: "mz_at0",
                value: "session",
                path: "/",
                domain: ".itunes.apple.com",
                httpOnly: true,
                secure: true
            ),
        ]

        #expect(cookies.buildCookieHeader(endpoint).first?.1 == "mz_at0=session")
    }
}
