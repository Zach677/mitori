import Foundation
import Security

@testable import Mitori

let failingWrite: @Sendable (Data, URL) throws -> Void = { _, _ in
    throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
}

@MainActor
final class SessionBridgeStub: AppleSessionBridging {
    struct LoginRequest {
        var email: String
        var password: String
        var code: String
        var deviceIdentifier: String
        var probeBundleID: String
    }

    var loginResult: SessionRefreshResult?
    var refreshResult: SessionRefreshResult?
    var reauthenticateResult: SessionRefreshResult?
    var loginRequests: [LoginRequest] = []
    var beforeLogin: (() async -> Void)?
    var beforeRefresh: (() async -> Void)?
    private(set) var refreshCallCount = 0

    init(
        loginResult: SessionRefreshResult? = nil,
        refreshResult: SessionRefreshResult? = nil,
        reauthenticateResult: SessionRefreshResult? = nil
    ) {
        self.loginResult = loginResult
        self.refreshResult = refreshResult
        self.reauthenticateResult = reauthenticateResult
    }

    func login(
        email: String,
        password: String,
        code: String,
        deviceIdentifier: String,
        probeBundleID: String
    ) async throws -> SessionRefreshResult {
        loginRequests.append(LoginRequest(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier,
            probeBundleID: probeBundleID
        ))
        await beforeLogin?()
        return try requiredResult(loginResult, fallback: .unknown("Missing login result"))
    }

    func reauthenticate(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret,
        code: String
    ) async throws -> SessionRefreshResult {
        try requiredResult(reauthenticateResult, fallback: .unknown("Missing reauthenticate result"))
    }

    func refreshBalance(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret
    ) async throws -> SessionRefreshResult {
        refreshCallCount += 1
        await beforeRefresh?()
        return try requiredResult(refreshResult, fallback: .unknown("Missing refresh result"))
    }

    private func requiredResult(
        _ result: SessionRefreshResult?,
        fallback: MitoriError
    ) throws -> SessionRefreshResult {
        guard let result else { throw fallback }
        return result
    }
}

@MainActor
final class RefreshGate {
    private var hasStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

final class FailingDeleteSecretBackend: SecretKeyValueStore {
    private var storage: [String: Data] = [:]

    func data(for key: String, allowsAuthenticationUI _: Bool) throws -> Data? {
        storage[key]
    }

    func set(_ data: Data, for key: String, allowsAuthenticationUI _: Bool) throws {
        storage[key] = data
    }

    func removeValue(for _: String, allowsAuthenticationUI _: Bool) throws {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecNotAvailable))
    }
}

final class BlockingWriteGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var hasStarted = false
    private var isReleased = false

    func suspend() {
        condition.lock()
        hasStarted = true
        condition.broadcast()
        while !isReleased {
            condition.wait()
        }
        condition.unlock()
    }

    func waitUntilStarted() {
        condition.lock()
        while !hasStarted {
            condition.wait()
        }
        condition.unlock()
    }

    func release() {
        condition.lock()
        isReleased = true
        condition.broadcast()
        condition.unlock()
    }
}
