import Foundation

/// Inteiro sem sinal grande, só com o que o SRP precisa: somar, subtrair, multiplicar e potências módulo N
/// (Montgomery, sem divisões). Palavras de 32 bits, a menos significativa primeiro, sem zeros no fim.
public struct BigUInt: Equatable, Comparable, Sendable {
    var limbs: [UInt32]

    init(limbs: [UInt32]) {
        var l = limbs
        while l.last == 0 { l.removeLast() }
        self.limbs = l
    }

    public init(_ value: UInt64) {
        self.init(limbs: [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)])
    }

    /// De bytes big-endian.
    public init(bytes: [UInt8]) {
        var l = [UInt32](repeating: 0, count: (bytes.count + 3) / 4)
        for (i, b) in bytes.reversed().enumerated() { l[i / 4] |= UInt32(b) << (UInt32(i % 4) * 8) }
        self.init(limbs: l)
    }

    public var isZero: Bool { limbs.isEmpty }

    public var bitWidth: Int {
        guard let top = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    /// Bytes big-endian sem zeros à esquerda (zero é [0]).
    public var bytes: [UInt8] {
        var out: [UInt8] = []
        for limb in limbs.reversed() {
            for s in stride(from: 24, through: 0, by: -8) { out.append(UInt8(truncatingIfNeeded: limb >> UInt32(s))) }
        }
        let trimmed = Array(out.drop { $0 == 0 })
        return trimmed.isEmpty ? [0] : trimmed
    }

    /// Bytes big-endian com zeros à esquerda até [count].
    public func padded(_ count: Int) -> [UInt8] {
        let b = isZero ? [] : bytes
        return [UInt8](repeating: 0, count: max(0, count - b.count)) + b
    }

    func bit(_ i: Int) -> Bool {
        let w = i / 32
        return w < limbs.count && (limbs[w] >> UInt32(i % 32)) & 1 == 1
    }

    public static func < (a: BigUInt, b: BigUInt) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] {
            return a.limbs[i] < b.limbs[i]
        }
        return false
    }

    public static func + (a: BigUInt, b: BigUInt) -> BigUInt {
        var out = [UInt32](repeating: 0, count: max(a.limbs.count, b.limbs.count) + 1)
        var carry: UInt64 = 0
        for i in 0..<out.count - 1 {
            let s = UInt64(i < a.limbs.count ? a.limbs[i] : 0) + UInt64(i < b.limbs.count ? b.limbs[i] : 0) + carry
            out[i] = UInt32(truncatingIfNeeded: s)
            carry = s >> 32
        }
        out[out.count - 1] = UInt32(carry)
        return BigUInt(limbs: out)
    }

    /// a − b, com a ≥ b.
    public static func - (a: BigUInt, b: BigUInt) -> BigUInt {
        precondition(!(a < b), "BigUInt: subtração negativa")
        var out = a.limbs
        var borrow: Int64 = 0
        for i in 0..<out.count {
            var d = Int64(out[i]) - Int64(i < b.limbs.count ? b.limbs[i] : 0) - borrow
            borrow = 0
            if d < 0 { d += 1 << 32; borrow = 1 }
            out[i] = UInt32(d)
        }
        return BigUInt(limbs: out)
    }

    public static func * (a: BigUInt, b: BigUInt) -> BigUInt {
        guard !a.isZero, !b.isZero else { return BigUInt(limbs: []) }
        var out = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            let ai = UInt64(a.limbs[i])
            for j in 0..<b.limbs.count {
                let s = UInt64(out[i + j]) + ai * UInt64(b.limbs[j]) + carry
                out[i + j] = UInt32(truncatingIfNeeded: s)
                carry = s >> 32
            }
            out[i + b.limbs.count] = UInt32(carry)
        }
        return BigUInt(limbs: out)
    }
}

/// Aritmética módulo um N ímpar (Montgomery).
public struct Montgomery: Sendable {
    let n: [UInt32]
    let count: Int
    let n0inv: UInt32
    /// R² mod N (R = 2^(32·count)).
    let r2: [UInt32]
    public let modulus: BigUInt

    public init(modulus: BigUInt) {
        precondition(modulus.limbs.first.map { $0 & 1 == 1 } ?? false, "Montgomery: N tem de ser ímpar")
        self.modulus = modulus
        n = modulus.limbs
        count = n.count
        // −N⁻¹ mod 2^32 (Newton).
        var inv: UInt32 = 1
        for _ in 0..<5 { inv = inv &* (2 &- n[0] &* inv) }
        n0inv = 0 &- inv
        // R² mod N: 1 dobrado 2·32·count vezes, sempre reduzido.
        var r = BigUInt(1)
        for _ in 0..<(64 * count) {
            r = r + r
            if !(r < modulus) { r = r - modulus }
        }
        r2 = Self.pad(r.limbs, count)
    }

    static func pad(_ l: [UInt32], _ count: Int) -> [UInt32] { l + [UInt32](repeating: 0, count: max(0, count - l.count)) }

    /// a·b·R⁻¹ mod N (CIOS), a e b < N com [count] palavras.
    func mul(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var t = [UInt32](repeating: 0, count: count + 2)
        for i in 0..<count {
            var c: UInt64 = 0
            let ai = UInt64(a[i])
            for j in 0..<count {
                let s = UInt64(t[j]) + ai * UInt64(b[j]) + c
                t[j] = UInt32(truncatingIfNeeded: s)
                c = s >> 32
            }
            var s = UInt64(t[count]) + c
            t[count] = UInt32(truncatingIfNeeded: s)
            t[count + 1] = UInt32(s >> 32)
            let m = t[0] &* n0inv
            c = (UInt64(t[0]) + UInt64(m) * UInt64(n[0])) >> 32
            for j in 1..<count {
                s = UInt64(t[j]) + UInt64(m) * UInt64(n[j]) + c
                t[j - 1] = UInt32(truncatingIfNeeded: s)
                c = s >> 32
            }
            s = UInt64(t[count]) + c
            t[count - 1] = UInt32(truncatingIfNeeded: s)
            t[count] = t[count + 1] &+ UInt32(s >> 32)
        }
        var r = BigUInt(limbs: Array(t[0...count]))
        if !(r < modulus) { r = r - modulus }
        return Self.pad(r.limbs, count)
    }

    /// x mod N, para x < R·N (x = alto·R + baixo, cada metade tratada à parte).
    func reduce(_ x: BigUInt) -> [UInt32] {
        if x < modulus { return Self.pad(x.limbs, count) }
        let lo = BigUInt(limbs: Array(x.limbs.prefix(count)))
        let hi = BigUInt(limbs: Array(x.limbs.dropFirst(count)))
        precondition(hi < modulus, "Montgomery.reduce: número grande demais")
        // mul(alto, R²) = alto·R (na forma de Montgomery é alto·R·R); mul(isso, R²) e depois mul(…, 1) dão alto·R mod N.
        let hiPart = mul(mul(Self.pad(hi.limbs, count), r2), r2)
        let hiValue = BigUInt(limbs: mul(hiPart, Self.pad([1], count)))
        var loValue = lo
        while !(loValue < modulus) { loValue = loValue - modulus }
        var sum = hiValue + loValue
        if !(sum < modulus) { sum = sum - modulus }
        return Self.pad(sum.limbs, count)
    }

    /// a·b mod N.
    public func multiply(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        BigUInt(limbs: mul(mul(reduce(a), reduce(b)), r2))
    }

    /// base^exp mod N.
    public func power(_ base: BigUInt, _ exp: BigUInt) -> BigUInt {
        let one = Self.pad([1], count)
        let baseM = mul(reduce(base), r2)
        var x = mul(one, r2) // R mod N (o 1 na forma de Montgomery)
        for i in stride(from: exp.bitWidth - 1, through: 0, by: -1) {
            x = mul(x, x)
            if exp.bit(i) { x = mul(x, baseM) }
        }
        return BigUInt(limbs: mul(x, one))
    }
}
