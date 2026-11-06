import Foundation
import Security

/// Passwords and pre-shared keys, kept by the privileged helper in root-only files.
///
/// The app sends a secret to the helper when you save it and never reads it back:
/// connecting just tells the helper which connection to use. The helper only uses
/// a saved secret with the gateway and username it was saved with.
///
/// (Secrets used to live in the Keychain. macOS ties Keychain access to each exact
/// build of an app without an Apple Team ID, so every update asked for your
/// password again. `migrateFromKeychain` moves old secrets over once.)
enum Secrets {
    struct Saved: Equatable { var password = false; var psk = false }
    struct Failure: Error { let message: String }

    /// Which secrets are saved for this connection's current gateway and username.
    static func status(_ p: Profile) -> Saved {
        guard let gw = gateway(p), !p.username.isEmpty,
              let reply = try? HelperClient.send(request(["cmd": "secrets-status", "id": p.id,
                                                           "gateway": gw, "username": clean(p.username)]), timeout: 5)
        else { return Saved() }
        return parse(reply)
    }

    /// Saves the secrets given (nil keeps the saved one if it still applies).
    @discardableResult
    static func save(_ p: Profile, password: String?, psk: String?, forgetPassword: Bool = false) throws -> Saved {
        guard let gw = gateway(p), !p.username.isEmpty else {
            throw Failure(message: "Enter the gateway and username before saving a password or key")
        }
        var fields = ["cmd": "secrets-set", "id": p.id, "gateway": gw, "username": clean(p.username)]
        if let password, !password.isEmpty { fields["password"] = clean(password) }
        if let psk, !psk.isEmpty { fields["psk"] = clean(psk) }
        if forgetPassword { fields["forget_password"] = "1" }
        do { return parse(try HelperClient.send(request(fields), timeout: 10)) }
        catch let e as HelperClient.Failure { throw Failure(message: e.message) }
    }

    static func copy(from: String, to: String) {
        _ = try? HelperClient.send(request(["cmd": "secrets-copy", "id": to, "from": from]), timeout: 5)
    }

    static func delete(_ id: String) {
        _ = try? HelperClient.send(request(["cmd": "secrets-delete", "id": id]), timeout: 5)
    }

    /// Moves secrets saved by older versions from the Keychain to the helper.
    /// Reading them may make macOS ask for your password one last time.
    static func migrateFromKeychain(_ profiles: [Profile]) {
        for p in profiles where LegacyKeychain.exists(p.id, .password) || LegacyKeychain.exists(p.id, .psk) {
            let pw = LegacyKeychain.get(p.id, .password), psk = LegacyKeychain.get(p.id, .psk)
            guard (try? save(p, password: pw, psk: psk)) != nil else { continue }
            LegacyKeychain.delete(p.id, .password)
            LegacyKeychain.delete(p.id, .psk)
        }
    }

    // MARK: helpers

    private static func gateway(_ p: Profile) -> String? {
        let g = p.gateway.trimmingCharacters(in: .whitespaces)
        return g.isEmpty ? nil : g
    }

    private static func clean(_ s: String) -> String {
        s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
    }

    private static func request(_ fields: [String: String]) -> String {
        fields.map { "\($0.key)=\($0.value)\n" }.joined() + "\n"
    }

    private static func parse(_ reply: String) -> Saved {
        Saved(password: reply.contains("password=1"), psk: reply.contains("psk=1"))
    }
}

/// Keychain items written by Passage before 0.2, read once for migration.
enum LegacyKeychain {
    enum Secret: String { case password, psk }

    private static func query(_ id: String, _ s: Secret) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Passage",
         kSecAttrAccount as String: "\(id).\(s.rawValue)"]
    }

    /// Whether an item exists, without reading it (no permission prompt).
    static func exists(_ id: String, _ s: Secret) -> Bool {
        var q = query(id, s)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ id: String, _ s: Secret) -> String {
        var q = query(id, s)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    static func delete(_ id: String, _ s: Secret) {
        SecItemDelete(query(id, s) as CFDictionary)
    }
}
