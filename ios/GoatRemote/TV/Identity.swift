import Foundation
import RemoteCore
import Security

/// A identidade deste iPhone perante as TVs: uma chave RSA e um certificado auto-assinado, no Keychain. A TV guarda o
/// certificado quando se emparelha e daí em diante só aceita o comando com ele.
enum Identity {
    struct Loaded {
        let identity: SecIdentity
        let certificate: [UInt8]
        let key: RSAKey
    }

    enum Failure: Error {
        case keychain(OSStatus)
        case keyGeneration(String)
    }

    private static let label = "GoatRemote"
    private static let tag = Data("cc.slokker.goatremote.identity".utf8)
    private static let lock = NSLock()
    private static var cached: Loaded?

    /// A identidade (feita na primeira vez).
    static func load() throws -> Loaded {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let loaded = try existing() ?? create()
        cached = loaded
        return loaded
    }

    private static func existing() throws -> Loaded? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let items = result as? [SecIdentity] else { throw Failure.keychain(status) }
        for identity in items {
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert,
                  SecCertificateCopySubjectSummary(cert) as String? == label else { continue }
            let der = Array(SecCertificateCopyData(cert) as Data)
            if let key = RSAKey(certificate: der) { return Loaded(identity: identity, certificate: der, key: key) }
        }
        return nil
    }

    private static func create() throws -> Loaded {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: tag,
                kSecAttrLabel: label,
                // Os Atalhos/Siri podem mandar teclas com o iPhone bloqueado.
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as [CFString: Any],
        ]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw Failure.keyGeneration(error.map { String(describing: $0.takeRetainedValue()) } ?? "?")
        }
        var serial = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7F
        let now = Date()
        let tbs = Certificate.tbs(publicKey: Array(pkcs1), commonName: label, serial: serial,
                                  notBefore: now.addingTimeInterval(-86_400), notAfter: now.addingTimeInterval(20 * 365 * 86_400))
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(tbs) as CFData, &error) as Data? else {
            throw Failure.keyGeneration(error.map { String(describing: $0.takeRetainedValue()) } ?? "assinatura")
        }
        let der = Certificate.assemble(tbs: tbs, signature: Array(signature))
        guard let cert = SecCertificateCreateWithData(nil, Data(der) as CFData) else { throw Failure.keyGeneration("certificado") }
        let add: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert,
            kSecAttrLabel: label,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure.keychain(status) }
        guard let loaded = try existing() else { throw Failure.keychain(errSecItemNotFound) }
        return loaded
    }
}
