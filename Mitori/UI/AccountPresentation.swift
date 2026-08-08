struct AccountPresentation {
    let name: String
    let email: String?
    let windowTitle: String
    let appleID: String
    let deviceIdentifier: String

    init(
        account: StoredAccountMeta,
        accountIndex: Int,
        hidesPersonalInformation: Bool
    ) {
        guard hidesPersonalInformation else {
            name = account.displayName
            email = account.email
            windowTitle = account.displayName
            appleID = account.appleID
            deviceIdentifier = account.deviceIdentifier
            return
        }

        name = "Account \(accountIndex + 1)"
        email = nil
        windowTitle = "Account Details"
        appleID = "Hidden"
        deviceIdentifier = "Hidden"
    }
}
