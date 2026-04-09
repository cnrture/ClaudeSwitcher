import Foundation

struct SwapAccount: Identifiable {
    let number: Int
    let email: String
    let organizationName: String
    let organizationUuid: String

    var id: Int { number }

    var shortEmail: String {
        email.contains("@") ? String(email.prefix(while: { $0 != "@" })) : email
    }
}

@MainActor
class ClaudeSwapManager: ObservableObject {
    @Published var accounts: [SwapAccount] = []
    @Published var activeAccount: SwapAccount?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var backupDir: URL { home.appendingPathComponent(".claude-swap-backup") }
    private var configsDir: URL { backupDir.appendingPathComponent("configs") }
    private var sequenceFile: URL { backupDir.appendingPathComponent("sequence.json") }

    init() {
        reload()
    }

    func reload() {
        let seq = readSequence()
        let activeNum = seq?["activeAccountNumber"] as? Int

        if let accountsDict = seq?["accounts"] as? [String: [String: Any]] {
            accounts = accountsDict.compactMap { (key, value) -> SwapAccount? in
                guard let num = Int(key) else { return nil }
                return SwapAccount(
                    number: num,
                    email: value["email"] as? String ?? "",
                    organizationName: value["organizationName"] as? String ?? "",
                    organizationUuid: value["organizationUuid"] as? String ?? ""
                )
            }.sorted { $0.number < $1.number }

            activeAccount = accounts.first { $0.number == activeNum }
        } else {
            accounts = []
            activeAccount = nil
        }
    }

    func addCurrentAccount() {
        isLoading = true
        errorMessage = nil

        Task.detached { [self] in
            let result = await self.performAddCurrentAccount()
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success:
                    self.reload()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func switchToAccount(_ number: Int) {
        isLoading = true
        errorMessage = nil

        Task.detached { [self] in
            let result = await self.performSwitch(to: number)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success:
                    self.reload()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func removeAccount(_ number: Int) {
        isLoading = true
        errorMessage = nil

        Task.detached { [self] in
            let result = await self.performRemove(number)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success:
                    self.reload()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Core Operations (run off main thread)

    private func performAddCurrentAccount() async -> Result<Void, Error> {
        do {
            try ensureDirectories()

            guard let configFile = findClaudeConfig() else {
                return .failure(SwapError.message("Claude config not found"))
            }
            let configText = try String(contentsOf: configFile, encoding: .utf8)
            let config = try parseJSON(configText)

            guard let oauthAccount = config["oauthAccount"] as? [String: Any] else {
                return .failure(SwapError.message("No oauthAccount in config"))
            }
            guard let email = oauthAccount["emailAddress"] as? String else {
                return .failure(SwapError.message("No email in oauthAccount"))
            }
            let orgUuid = oauthAccount["organizationUuid"] as? String ?? ""
            let orgName = oauthAccount["organizationName"] as? String ?? ""
            let accountUuid = oauthAccount["accountUuid"] as? String ?? ""

            guard let credentials = readCurrentCredentials() else {
                return .failure(SwapError.message("Cannot read current credentials"))
            }

            var seq = readSequence() ?? [
                "activeAccountNumber": 1,
                "lastUpdated": ISO8601DateFormatter().string(from: Date()),
                "sequence": [Int](),
                "accounts": [String: Any](),
            ]

            var accountsDict = seq["accounts"] as? [String: Any] ?? [:]
            var sequence = seq["sequence"] as? [Int] ?? []

            // Check existing
            let existing = accountsDict.first { (_, value) in
                guard let v = value as? [String: Any] else { return false }
                return v["email"] as? String == email && v["organizationUuid"] as? String == orgUuid
            }

            let accountNumber: Int
            if let existing = existing {
                accountNumber = Int(existing.key) ?? 1
            } else {
                accountNumber = (accountsDict.keys.compactMap { Int($0) }.max() ?? 0) + 1
                sequence.append(accountNumber)
            }

            writeAccountCredentials(number: accountNumber, email: email, data: credentials)
            writeAccountConfig(number: accountNumber, email: email, configText: configText)

            accountsDict["\(accountNumber)"] = [
                "email": email,
                "uuid": accountUuid,
                "organizationUuid": orgUuid,
                "organizationName": orgName,
                "added": ISO8601DateFormatter().string(from: Date()),
            ] as [String: Any]

            seq["activeAccountNumber"] = accountNumber
            seq["lastUpdated"] = ISO8601DateFormatter().string(from: Date())
            seq["sequence"] = sequence
            seq["accounts"] = accountsDict

            try writeSequence(seq)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func performSwitch(to targetNumber: Int) async -> Result<Void, Error> {
        do {
            guard let seq = readSequence() else {
                return .failure(SwapError.message("No swap configuration found"))
            }
            guard let accountsDict = seq["accounts"] as? [String: [String: Any]] else {
                return .failure(SwapError.message("No accounts found"))
            }
            guard let activeNumber = seq["activeAccountNumber"] as? Int else {
                return .failure(SwapError.message("No active account"))
            }
            if targetNumber == activeNumber { return .success(()) }

            guard let targetAccount = accountsDict["\(targetNumber)"] else {
                return .failure(SwapError.message("Account \(targetNumber) not found"))
            }
            let targetEmail = targetAccount["email"] as? String ?? ""
            let activeEmail = accountsDict["\(activeNumber)"]?["email"] as? String ?? ""

            guard let currentCredentials = readCurrentCredentials() else {
                return .failure(SwapError.message("Cannot read current credentials"))
            }
            guard let configFile = findClaudeConfig() else {
                return .failure(SwapError.message("Claude config not found"))
            }
            let currentConfigText = try String(contentsOf: configFile, encoding: .utf8)

            // Backup current
            writeAccountCredentials(number: activeNumber, email: activeEmail, data: currentCredentials)
            writeAccountConfig(number: activeNumber, email: activeEmail, configText: currentConfigText)

            // Read target
            guard let targetCredentials = readAccountCredentials(number: targetNumber, email: targetEmail) else {
                return .failure(SwapError.message("No credentials backup for account \(targetNumber)"))
            }
            guard let targetConfigText = readAccountConfig(number: targetNumber, email: targetEmail) else {
                return .failure(SwapError.message("No config backup for account \(targetNumber)"))
            }

            // Write target as current
            guard writeCurrentCredentials(targetCredentials) else {
                _ = writeCurrentCredentials(currentCredentials)
                return .failure(SwapError.message("Failed to write target credentials"))
            }

            // Merge config
            guard mergeAndWriteConfig(configFile: configFile, current: currentConfigText, target: targetConfigText) else {
                _ = writeCurrentCredentials(currentCredentials)
                try currentConfigText.write(to: configFile, atomically: true, encoding: .utf8)
                return .failure(SwapError.message("Failed to merge config"))
            }

            // Update sequence
            var updated = seq
            updated["activeAccountNumber"] = targetNumber
            updated["lastUpdated"] = ISO8601DateFormatter().string(from: Date())
            try writeSequence(updated)

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func performRemove(_ accountNumber: Int) async -> Result<Void, Error> {
        do {
            guard var seq = readSequence() else {
                return .failure(SwapError.message("No swap configuration"))
            }
            guard var accountsDict = seq["accounts"] as? [String: Any] else {
                return .failure(SwapError.message("No accounts"))
            }
            guard let account = accountsDict["\(accountNumber)"] as? [String: Any] else {
                return .failure(SwapError.message("Account not found"))
            }
            let email = account["email"] as? String ?? ""

            deleteAccountCredentials(number: accountNumber, email: email)
            let configBackup = configsDir.appendingPathComponent(".claude-config-\(accountNumber)-\(email).json")
            try? FileManager.default.removeItem(at: configBackup)

            accountsDict.removeValue(forKey: "\(accountNumber)")
            var sequence = seq["sequence"] as? [Int] ?? []
            sequence.removeAll { $0 == accountNumber }

            seq["accounts"] = accountsDict
            seq["sequence"] = sequence
            seq["lastUpdated"] = ISO8601DateFormatter().string(from: Date())
            try writeSequence(seq)

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Config Resolution

    private func findClaudeConfig() -> URL? {
        let dotClaude = home.appendingPathComponent(".claude/.claude.json")
        let legacy = home.appendingPathComponent(".claude.json")
        let fm = FileManager.default

        let candidates = [dotClaude, legacy].filter { fm.fileExists(atPath: $0.path) }
        if candidates.isEmpty { return nil }
        if candidates.count == 1 { return candidates[0] }

        let withOauth = candidates.filter { hasOauthAccount($0) }
        let pool = withOauth.isEmpty ? candidates : withOauth
        return pool.max { a, b in
            let aDate = (try? fm.attributesOfItem(atPath: a.path)[.modificationDate] as? Date) ?? .distantPast
            let bDate = (try? fm.attributesOfItem(atPath: b.path)[.modificationDate] as? Date) ?? .distantPast
            return aDate < bDate
        }
    }

    private func hasOauthAccount(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let dict = try? parseJSON(text) else { return false }
        return dict["oauthAccount"] != nil
    }

    // MARK: - Credentials

    private func readCurrentCredentials() -> String? {
        KeychainHelper.read(service: "Claude Code-credentials")
    }

    @discardableResult
    private func writeCurrentCredentials(_ data: String) -> Bool {
        KeychainHelper.write(service: "Claude Code-credentials", account: NSUserName(), data: data)
    }

    private func readAccountCredentials(number: Int, email: String) -> String? {
        KeychainHelper.read(service: "claude-code", account: "account-\(number)-\(email)")
    }

    @discardableResult
    private func writeAccountCredentials(number: Int, email: String, data: String) -> Bool {
        KeychainHelper.write(service: "claude-code", account: "account-\(number)-\(email)", data: data)
    }

    private func deleteAccountCredentials(number: Int, email: String) {
        KeychainHelper.delete(service: "claude-code", account: "account-\(number)-\(email)")
    }

    // MARK: - Config Backup

    private func readAccountConfig(number: Int, email: String) -> String? {
        let file = configsDir.appendingPathComponent(".claude-config-\(number)-\(email).json")
        return try? String(contentsOf: file, encoding: .utf8)
    }

    private func writeAccountConfig(number: Int, email: String, configText: String) {
        try? FileManager.default.createDirectory(at: configsDir, withIntermediateDirectories: true)
        let file = configsDir.appendingPathComponent(".claude-config-\(number)-\(email).json")
        try? configText.write(to: file, atomically: true, encoding: .utf8)
        setOwnerOnly(file)
    }

    private func mergeAndWriteConfig(configFile: URL, current: String, target: String) -> Bool {
        guard var currentDict = try? parseJSON(current),
              let targetDict = try? parseJSON(target),
              let targetOauth = targetDict["oauthAccount"] else { return false }

        currentDict["oauthAccount"] = targetOauth
        guard let data = try? JSONSerialization.data(withJSONObject: currentDict, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return false }

        do {
            try text.write(to: configFile, atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }

    // MARK: - Sequence File

    private func readSequence() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: sequenceFile.path),
              let data = try? Data(contentsOf: sequenceFile),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }

    private func writeSequence(_ dict: [String: Any]) throws {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        let tmp = backupDir.appendingPathComponent(".\(ProcessInfo.processInfo.processIdentifier).tmp")
        try data.write(to: tmp)
        setOwnerOnly(tmp)
        _ = try FileManager.default.replaceItemAt(sequenceFile, withItemAt: tmp)
    }

    private func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: configsDir, withIntermediateDirectories: true)
    }

    private func setOwnerOnly(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func parseJSON(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SwapError.message("Invalid JSON")
        }
        return dict
    }
}

enum SwapError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let msg): return msg }
    }
}
