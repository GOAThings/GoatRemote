/// Os endereços na rede de casa (o GoatLauncher em 6470, o GoatTV em 6471): http://<host>:<porta>/<caminho>, com um
/// IPv6 entre parênteses retos (sem eles o URL não se lê). O mesmo que o Android faz (data/LanHttp.url).
public enum LanURL {
    public static func string(host: String, port: Int, path: String) -> String {
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "http://\(h):\(port)/\(path)"
    }
}
