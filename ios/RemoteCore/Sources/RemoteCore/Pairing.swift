import Foundation

/// O emparelhamento (porta 6467): o telemóvel pede, a TV mostra um código de 6 caracteres hexadecimais e o telemóvel
/// manda um segredo feito com o código e as chaves dos dois certificados. Daí em diante a TV aceita este certificado
/// no comando (porta 6466).
///
/// PairingMessage: protocol_version 1, status 2 (200 = OK), e um destes: pairing_request 10 {service_name 1,
/// client_name 2}, pairing_request_ack 11, pairing_option 20 {input_encodings 1, output_encodings 2, preferred_role 3},
/// pairing_configuration 30 {encoding 1, client_role 2}, pairing_configuration_ack 31, pairing_secret 40 {secret 1},
/// pairing_secret_ack 41. Encoding {type 1 (3 = hexadecimal), symbol_length 2}; role 1 = quem escreve o código.
public enum Pairing {
    public static let port: UInt16 = 6467
    public static let codeLength = 6

    public enum Failure: Error, Equatable, Sendable {
        /// A TV recusou (estado diferente de 200).
        case rejected(Int)
        case unexpected(String)
    }

    static func message(_ field: Int, _ body: Proto) -> Data {
        Frame.encode(Proto().varint(1, 2).varint(2, 200).message(field, body))
    }

    static let hexEncoding = Proto().varint(1, 3).varint(2, codeLength)

    public static func request(clientName: String) -> Data {
        message(10, Proto().string(1, "atvremote").string(2, clientName))
    }

    public static let options = message(20, Proto().message(1, hexEncoding).varint(3, 1))

    public static let configuration = message(30, Proto().message(1, hexEncoding).varint(2, 1))

    public static func secretMessage(_ secret: [UInt8]) -> Data { message(40, Proto().bytes(1, secret)) }

    /// Confere uma resposta da TV: estado 200 e o campo esperado.
    public static func check(_ frame: [UInt8], expecting field: Int) throws {
        let m = try ProtoMessage(frame)
        let status = m.int(2)
        guard status == 200 else { throw Failure.rejected(status) }
        guard m.has(field) else { throw Failure.unexpected("esperava \(field), veio \(m)") }
    }

    /// O código como a TV o mostra (6 caracteres hexadecimais, maiúsculas), ou nil.
    public static func normalize(_ code: String) -> String? {
        let clean = code.uppercased().filter { !$0.isWhitespace }
        guard clean.count == codeLength, clean.allSatisfy({ $0.isHexDigit }) else { return nil }
        return clean
    }

    /// O segredo: SHA-256 de módulo e expoente do telemóvel, módulo e expoente da TV e dos 2 últimos bytes do código.
    /// O primeiro byte do código é o primeiro do segredo: se não bater, o código está errado (nil).
    public static func secret(code: String, client: RSAKey, server: RSAKey) -> [UInt8]? {
        guard let code = normalize(code) else { return nil }
        let bytes = stride(from: 0, to: code.count, by: 2).map { i -> UInt8 in
            let start = code.index(code.startIndex, offsetBy: i)
            return UInt8(code[start..<code.index(start, offsetBy: 2)], radix: 16)!
        }
        let alpha = SHA.sha256(client.modulus + client.exponent + server.modulus + server.exponent + Array(bytes[1...]))
        return alpha[0] == bytes[0] ? alpha : nil
    }

    /// Os passos todos, com a ligação dada pelo chamador: [send] manda bytes, [receive] devolve a próxima mensagem e
    /// [askCode] espera pelo código que a pessoa lê na TV (com true quando o anterior estava errado: a TV continua
    /// à espera, não é preciso recomeçar).
    public static func run(
        clientName: String,
        client: RSAKey,
        server: RSAKey,
        send: (Data) async throws -> Void,
        receive: () async throws -> [UInt8],
        askCode: (_ retry: Bool) async throws -> String
    ) async throws {
        try await send(request(clientName: clientName))
        try check(try await receive(), expecting: 11)
        try await send(options)
        try check(try await receive(), expecting: 20)
        try await send(configuration)
        try check(try await receive(), expecting: 31)
        // A TV mostra agora o código.
        var retry = false
        var secret: [UInt8]?
        while secret == nil {
            secret = Self.secret(code: try await askCode(retry), client: client, server: server)
            retry = true
        }
        try await send(secretMessage(secret!))
        try check(try await receive(), expecting: 41)
    }
}
