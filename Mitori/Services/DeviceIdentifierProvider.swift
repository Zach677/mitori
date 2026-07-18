import ApplePackage

enum DeviceIdentifierProvider {
    static func make() -> String {
        (try? DeviceIdentifier.system()) ?? DeviceIdentifier.random()
    }
}
