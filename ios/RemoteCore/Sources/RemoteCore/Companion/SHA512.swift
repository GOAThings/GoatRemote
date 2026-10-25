import Foundation

/// SHA-512, HMAC-SHA512 e HKDF-SHA512 sem dependências (para o SRP e as chaves da Apple TV; CryptoKit não existe
/// em Linux, onde se testa o núcleo).
public enum SHA512 {
    public static func hash(_ data: [UInt8]) -> [UInt8] {
        var h: [UInt64] = [0x6A09_E667_F3BC_C908, 0xBB67_AE85_84CA_A73B, 0x3C6E_F372_FE94_F82B, 0xA54F_F53A_5F1D_36F1, 0x510E_527F_ADE6_82D1, 0x9B05_688C_2B3E_6C1F, 0x1F83_D9AB_FB41_BD6B, 0x5BE0_CD19_137E_2179]
        var w = [UInt64](repeating: 0, count: 80)
        var m = data
        let bits = UInt64(data.count) &* 8
        m.append(0x80)
        while m.count % 128 != 112 { m.append(0) }
        m += [UInt8](repeating: 0, count: 8)
        for i in (0..<8).reversed() { m.append(UInt8(truncatingIfNeeded: bits >> (UInt64(i) * 8))) }
        for block in stride(from: 0, to: m.count, by: 128) {
            for i in 0..<16 {
                var v: UInt64 = 0
                for j in 0..<8 { v = v << 8 | UInt64(m[block + i * 8 + j]) }
                w[i] = v
            }
            for i in 16..<80 {
                let s0 = rotr(w[i - 15], 1) ^ rotr(w[i - 15], 8) ^ (w[i - 15] >> 7)
                let s1 = rotr(w[i - 2], 19) ^ rotr(w[i - 2], 61) ^ (w[i - 2] >> 6)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<80 {
                let s1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ s0 &+ maj)
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.flatMap { v in (0..<8).map { UInt8(truncatingIfNeeded: v >> (56 - UInt64($0) * 8)) } }
    }

    public static func hmac(key: [UInt8], _ message: [UInt8]) -> [UInt8] {
        var k = key.count > 128 ? hash(key) : key
        k += [UInt8](repeating: 0, count: 128 - k.count)
        return hash(k.map { $0 ^ 0x5C } + hash(k.map { $0 ^ 0x36 } + message))
    }

    /// HKDF (RFC 5869) com SHA-512.
    public static func hkdf(salt: [UInt8], info: [UInt8], key: [UInt8], length: Int = 32) -> [UInt8] {
        let prk = hmac(key: salt, key)
        var out: [UInt8] = []
        var t: [UInt8] = []
        var i: UInt8 = 1
        while out.count < length {
            t = hmac(key: prk, t + info + [i])
            out += t
            i += 1
        }
        return Array(out.prefix(length))
    }

    public static func hkdf(salt: String, info: String, key: [UInt8], length: Int = 32) -> [UInt8] {
        hkdf(salt: Array(salt.utf8), info: Array(info.utf8), key: key, length: length)
    }

    private static func rotr(_ v: UInt64, _ n: UInt64) -> UInt64 { (v >> n) | (v << (64 - n)) }

    private static let k: [UInt64] = [
        0x428A_2F98_D728_AE22, 0x7137_4491_23EF_65CD, 0xB5C0_FBCF_EC4D_3B2F, 0xE9B5_DBA5_8189_DBBC,
        0x3956_C25B_F348_B538, 0x59F1_11F1_B605_D019, 0x923F_82A4_AF19_4F9B, 0xAB1C_5ED5_DA6D_8118,
        0xD807_AA98_A303_0242, 0x1283_5B01_4570_6FBE, 0x2431_85BE_4EE4_B28C, 0x550C_7DC3_D5FF_B4E2,
        0x72BE_5D74_F27B_896F, 0x80DE_B1FE_3B16_96B1, 0x9BDC_06A7_25C7_1235, 0xC19B_F174_CF69_2694,
        0xE49B_69C1_9EF1_4AD2, 0xEFBE_4786_384F_25E3, 0x0FC1_9DC6_8B8C_D5B5, 0x240C_A1CC_77AC_9C65,
        0x2DE9_2C6F_592B_0275, 0x4A74_84AA_6EA6_E483, 0x5CB0_A9DC_BD41_FBD4, 0x76F9_88DA_8311_53B5,
        0x983E_5152_EE66_DFAB, 0xA831_C66D_2DB4_3210, 0xB003_27C8_98FB_213F, 0xBF59_7FC7_BEEF_0EE4,
        0xC6E0_0BF3_3DA8_8FC2, 0xD5A7_9147_930A_A725, 0x06CA_6351_E003_826F, 0x1429_2967_0A0E_6E70,
        0x27B7_0A85_46D2_2FFC, 0x2E1B_2138_5C26_C926, 0x4D2C_6DFC_5AC4_2AED, 0x5338_0D13_9D95_B3DF,
        0x650A_7354_8BAF_63DE, 0x766A_0ABB_3C77_B2A8, 0x81C2_C92E_47ED_AEE6, 0x9272_2C85_1482_353B,
        0xA2BF_E8A1_4CF1_0364, 0xA81A_664B_BC42_3001, 0xC24B_8B70_D0F8_9791, 0xC76C_51A3_0654_BE30,
        0xD192_E819_D6EF_5218, 0xD699_0624_5565_A910, 0xF40E_3585_5771_202A, 0x106A_A070_32BB_D1B8,
        0x19A4_C116_B8D2_D0C8, 0x1E37_6C08_5141_AB53, 0x2748_774C_DF8E_EB99, 0x34B0_BCB5_E19B_48A8,
        0x391C_0CB3_C5C9_5A63, 0x4ED8_AA4A_E341_8ACB, 0x5B9C_CA4F_7763_E373, 0x682E_6FF3_D6B2_B8A3,
        0x748F_82EE_5DEF_B2FC, 0x78A5_636F_4317_2F60, 0x84C8_7814_A1F0_AB72, 0x8CC7_0208_1A64_39EC,
        0x90BE_FFFA_2363_1E28, 0xA450_6CEB_DE82_BDE9, 0xBEF9_A3F7_B2C6_7915, 0xC671_78F2_E372_532B,
        0xCA27_3ECE_EA26_619C, 0xD186_B8C7_21C0_C207, 0xEADA_7DD6_CDE0_EB1E, 0xF57D_4F7F_EE6E_D178,
        0x06F0_67AA_7217_6FBA, 0x0A63_7DC5_A2C8_98A6, 0x113F_9804_BEF9_0DAE, 0x1B71_0B35_131C_471B,
        0x28DB_77F5_2304_7D84, 0x32CA_AB7B_40C7_2493, 0x3C9E_BE0A_15C9_BEBC, 0x431D_67C4_9C10_0D4C,
        0x4CC5_D4BE_CB3E_42B6, 0x597F_299C_FC65_7E2A, 0x5FCB_6FAB_3AD6_FAEC, 0x6C44_198C_4A47_5817,
    ]
}
