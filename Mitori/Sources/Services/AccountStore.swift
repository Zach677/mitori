import Foundation

actor AccountStore {
    private static let legacyDirectoryName = ["Store", "Peek"].joined()

    private let fileManager: FileManager
    private let fileURL: URL
    private let legacyFileURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        legacyBaseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let rootDirectory = baseDirectory
            ?? applicationSupportDirectory.appendingPathComponent("Mitori", isDirectory: true)
        fileURL = rootDirectory.appendingPathComponent("accounts.json")
        let resolvedLegacyBaseDirectory = legacyBaseDirectory
            ?? (
                baseDirectory == nil
                    ? applicationSupportDirectory.appendingPathComponent(Self.legacyDirectoryName, isDirectory: true)
                    : nil
            )
        legacyFileURL = resolvedLegacyBaseDirectory?.appendingPathComponent("accounts.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadAccounts() throws -> [StoredAccountMeta] {
        try migrateLegacyFileIfNeeded()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([StoredAccountMeta].self, from: data)
    }

    @discardableResult
    func upsert(_ meta: StoredAccountMeta) throws -> [StoredAccountMeta] {
        var accounts = try loadAccounts()
        accounts.removeAll { $0.id == meta.id }
        accounts.append(meta)
        accounts.sort { $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending }
        try persist(accounts)
        return accounts
    }

    @discardableResult
    func deleteAccount(id: String) throws -> [StoredAccountMeta] {
        let accounts = try loadAccounts().filter { $0.id != id }
        try persist(accounts)
        return accounts
    }

    private func persist(_ accounts: [StoredAccountMeta]) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(accounts)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func migrateLegacyFileIfNeeded() throws {
        guard !fileManager.fileExists(atPath: fileURL.path),
              let legacyFileURL,
              legacyFileURL.path != fileURL.path,
              fileManager.fileExists(atPath: legacyFileURL.path)
        else {
            return
        }

        try ensureDirectoryExists()
        try fileManager.copyItem(at: legacyFileURL, to: fileURL)
    }
}
