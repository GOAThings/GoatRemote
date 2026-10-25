import Foundation

/// SRP-6a do emparelhamento HomeKit/Companion (Apple TV): grupo de 3072 bits do RFC 5054, g = 5, SHA-512, utilizador
/// "Pair-Setup" e o PIN como palavra-passe. As conversões de bytes são as do srptools (o que a Apple TV aceita):
/// k e u com valores alinhados a 384 bytes; K = H(S) e a prova com S, A e B no tamanho mínimo.
public struct SRPClient: Sendable {
    public static let prime = BigUInt(bytes: hex(
        "ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b139b22514a08798e3404dd",
        "ef9519b3cd3a431b302b0a6df25f14374fe1356d6d51c245e485b576625e7ec6f44c42e9a637ed6b0bff5cb6f406b7ed",
        "ee386bfb5a899fa5ae9f24117c4b1fe649286651ece45b3dc2007cb8a163bf0598da48361c55d39a69163fa8fd24cf5f",
        "83655d23dca3ad961c62f356208552bb9ed529077096966d670c354e4abc9804f1746c08ca18217c32905e462e36ce3b",
        "e39e772c180e86039b2783a2ec07a28fb5c55df06f4c52c9de2bcbf6955817183995497cea956ae515d2261898fa0510",
        "15728e5a8aaac42dad33170d04507a33a85521abdf1cba64ecfb850458dbef0a8aea71575d060c7db3970f85a6e1e4c7",
        "abf5ae8cdb0933d71e8c94e04a25619dcee3d2261ad2ee6bf12ffa06d98a0864d87602733ec86a64521f2b18177b200c",
        "bbe117577a615d6c770988c0bad946e208e24fa074e5ab3143db5bfce0fd108e4b82d120a93ad2caffffffffffffffff"
    ))
    public static let generator = BigUInt(5)
    static let mont = Montgomery(modulus: prime)

    let a: BigUInt
    /// A, a enviar na M3 (tamanho mínimo).
    public let publicKey: [UInt8]

    /// [privateKey]: 32 bytes aleatórios.
    public init(privateKey: [UInt8]) {
        a = BigUInt(bytes: privateKey)
        publicKey = Self.mont.power(Self.generator, a).bytes
    }

    public struct Result: Sendable {
        /// M1: a prova deste lado.
        public let proof: [UInt8]
        /// M2: a prova que a TV tem de mandar.
        public let expectedServerProof: [UInt8]
        /// K: a chave de sessão (64 bytes).
        public let sessionKey: [UInt8]
    }

    /// Com o sal e o B da TV (M2) e o PIN; nil se B não servir (B mod N = 0).
    public func process(salt: [UInt8], serverPublicKey: [UInt8], pin: String) -> Result? {
        let n = Self.prime, g = Self.generator, mont = Self.mont
        let B = BigUInt(bytes: serverPublicKey)
        guard !(BigUInt(limbs: mont.reduce(B)).isZero) else { return nil }
        let A = BigUInt(bytes: publicKey)
        let k = BigUInt(bytes: SHA512.hash(n.bytes + g.padded(384)))
        let x = BigUInt(bytes: SHA512.hash(salt + SHA512.hash(Array("Pair-Setup:\(pin)".utf8))))
        let u = BigUInt(bytes: SHA512.hash(A.padded(384) + B.padded(384)))
        let kv = mont.multiply(k, mont.power(g, x))
        let b = BigUInt(limbs: mont.reduce(B))
        let base = kv < b || kv == b ? b - kv : b + n - kv
        let S = mont.power(base, a + u * x)
        let K = SHA512.hash(S.bytes)
        let hN = SHA512.hash(n.bytes), hG = SHA512.hash(g.bytes)
        let xor = BigUInt(bytes: zip(hN, hG).map { $0 ^ $1 }).bytes
        let hI = BigUInt(bytes: SHA512.hash(Array("Pair-Setup".utf8))).bytes
        let m1 = SHA512.hash(xor + hI + salt + A.bytes + B.bytes + K)
        let m2 = SHA512.hash(A.bytes + m1 + K)
        return Result(proof: m1, expectedServerProof: m2, sessionKey: K)
    }

    static func hex(_ parts: String...) -> [UInt8] {
        let s = Array(parts.joined().utf8)
        return stride(from: 0, to: s.count, by: 2).map { UInt8(String(decoding: s[$0..<$0 + 2], as: UTF8.self), radix: 16)! }
    }
}
