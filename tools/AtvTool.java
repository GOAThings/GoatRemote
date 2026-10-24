import java.io.*;
import java.math.BigInteger;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import java.security.interfaces.RSAPublicKey;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;
import javax.net.ssl.*;

/**
 * O protocolo do comando das Android TV (o da app Google TV, "Android TV Remote v2") dos dois lados, num só ficheiro:
 *
 *   java AtvTool.java server [pasta]          uma TV falsa: emparelhamento em :6467, comando em :6466 e, em
 *                                             127.0.0.1:7000, /code (o código no "ecrã"), /log e /state (para os testes)
 *   java AtvTool.java pair <ip> [pasta]       emparelha com uma TV a sério; o código lê-se de <pasta>/code.txt
 *   java AtvTool.java key <ip> KEY... [pasta] teclas (DPAD_UP, HOME, 23, …; "long:KEY" mantém premida)
 *   java AtvTool.java text <ip> "texto" [pasta]
 *   java AtvTool.java app <ip> <link> [pasta]
 *   java AtvTool.java status <ip> [pasta]     o que a TV conta ao ligar (ligada, app aberta, volume)
 *
 * A pasta (por omissão ./atv-state) guarda a identidade (chave e certificado) deste lado.
 */
public class AtvTool {
    static final int PAIRING_PORT = 6467, REMOTE_PORT = 6466, CONTROL_PORT = 7000;
    // Funcionalidades (RemoteConfigure.code1): PING, KEY, IME, POWER, VOLUME, APP_LINK.
    static final int FEATURES = 1 | 2 | 4 | 32 | 64 | 512;

    public static void main(String[] args) throws Exception {
        if (args.length == 0) { System.err.println("Uso: server | pair | key | text | app | status (ver o início do ficheiro)"); System.exit(2); }
        switch (args[0]) {
            case "server" -> new FakeTv(state(args, 1)).run();
            case "pair" -> Client.pair(args[1], state(args, 2));
            case "key" -> {
                List<String> keys = new ArrayList<>(Arrays.asList(args).subList(2, args.length));
                Path dir = Paths.get("atv-state");
                if (!keys.isEmpty() && keys.get(keys.size() - 1).contains("/")) dir = Paths.get(keys.remove(keys.size() - 1));
                Client.keys(args[1], dir, keys);
            }
            case "text" -> Client.text(args[1], args[2], state(args, 3));
            case "app" -> Client.app(args[1], args[2], state(args, 3));
            case "status" -> Client.status(args[1], state(args, 2));
            default -> { System.err.println("Comando desconhecido: " + args[0]); System.exit(2); }
        }
    }

    static Path state(String[] args, int i) { return Paths.get(args.length > i ? args[i] : "atv-state"); }

    // ---------------------------------------------------------------- Protobuf mínimo

    static final class W {
        final ByteArrayOutputStream out = new ByteArrayOutputStream();
        W varint(int field, long v) { tag(field, 0); putVarint(out, v); return this; }
        W bytes(int field, byte[] b) { tag(field, 2); putVarint(out, b.length); out.writeBytes(b); return this; }
        W string(int field, String s) { return bytes(field, s.getBytes(StandardCharsets.UTF_8)); }
        W msg(int field, W m) { return bytes(field, m.done()); }
        byte[] done() { return out.toByteArray(); }
        void tag(int field, int wire) { putVarint(out, ((long) field << 3) | wire); }
    }

    static void putVarint(ByteArrayOutputStream out, long v) {
        while ((v & ~0x7FL) != 0) { out.write((int) ((v & 0x7F) | 0x80)); v >>>= 7; }
        out.write((int) v);
    }

    static final class M {
        final Map<Integer, List<Object>> f = new LinkedHashMap<>();
        static M parse(byte[] d) {
            M m = new M();
            int[] p = {0};
            while (p[0] < d.length) {
                long tag = rv(d, p);
                int field = (int) (tag >>> 3);
                switch ((int) (tag & 7)) {
                    case 0 -> m.f.computeIfAbsent(field, k -> new ArrayList<>()).add(rv(d, p));
                    case 2 -> {
                        int len = (int) rv(d, p);
                        m.f.computeIfAbsent(field, k -> new ArrayList<>()).add(Arrays.copyOfRange(d, p[0], p[0] + len));
                        p[0] += len;
                    }
                    case 1 -> p[0] += 8;
                    case 5 -> p[0] += 4;
                    default -> throw new IllegalStateException("tipo desconhecido");
                }
            }
            return m;
        }
        static long rv(byte[] d, int[] p) {
            long r = 0; int s = 0;
            while (true) { int b = d[p[0]++] & 0xFF; r |= (long) (b & 0x7F) << s; if ((b & 0x80) == 0) return r; s += 7; }
        }
        boolean has(int field) { return f.containsKey(field); }
        long num(int field) { List<Object> l = f.get(field); return l == null ? 0 : (Long) l.get(l.size() - 1); }
        byte[] raw(int field) { List<Object> l = f.get(field); return l == null ? new byte[0] : (byte[]) l.get(l.size() - 1); }
        String str(int field) { return new String(raw(field), StandardCharsets.UTF_8); }
        M msg(int field) { return parse(raw(field)); }
        List<M> msgs(int field) {
            List<M> r = new ArrayList<>();
            for (Object o : f.getOrDefault(field, List.of())) r.add(parse((byte[]) o));
            return r;
        }
        @Override public String toString() { return f.keySet().toString(); }
    }

    static void send(OutputStream out, byte[] msg) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        putVarint(b, msg.length);
        b.writeBytes(msg);
        out.write(b.toByteArray());
        out.flush();
    }

    static byte[] read(InputStream in) throws IOException {
        int len = 0, shift = 0;
        while (true) {
            int b = in.read();
            if (b < 0) throw new EOFException();
            len |= (b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
        }
        return in.readNBytes(len);
    }

    // ---------------------------------------------------------------- Emparelhamento

    // PairingMessage: protocol_version 1, status 2 (200 = OK, 402 = segredo errado), e um destes:
    // pairing_request 10 {service_name 1, client_name 2}, pairing_request_ack 11 {server_name 1},
    // pairing_option 20 {input_encodings 1, output_encodings 2, preferred_role 3},
    // pairing_configuration 30 {encoding 1, client_role 2}, pairing_configuration_ack 31,
    // pairing_secret 40 {secret 1}, pairing_secret_ack 41 {secret 1}. Encoding {type 1 (3 = hex), symbol_length 2}.
    static byte[] pmsg(int status, int field, W body) {
        return new W().varint(1, 2).varint(2, status).msg(field, body).done();
    }

    static W hexEncoding() { return new W().varint(1, 3).varint(2, 6); }

    /** O segredo: SHA-256 de módulo e expoente do cliente, módulo e expoente do servidor e dos 2 últimos bytes do código. */
    static byte[] secret(RSAPublicKey client, RSAPublicKey server, byte[] codeTail) throws Exception {
        MessageDigest h = MessageDigest.getInstance("SHA-256");
        h.update(unsigned(client.getModulus()));
        h.update(unsigned(client.getPublicExponent()));
        h.update(unsigned(server.getModulus()));
        h.update(unsigned(server.getPublicExponent()));
        h.update(codeTail);
        return h.digest();
    }

    static byte[] unsigned(BigInteger v) {
        byte[] b = v.toByteArray();
        return b.length > 1 && b[0] == 0 ? Arrays.copyOfRange(b, 1, b.length) : b;
    }

    static String hex(byte[] b) {
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02X", x));
        return s.toString();
    }

    static byte[] unhex(String s) {
        byte[] b = new byte[s.length() / 2];
        for (int i = 0; i < b.length; i++) b[i] = (byte) Integer.parseInt(s.substring(2 * i, 2 * i + 2), 16);
        return b;
    }

    // ---------------------------------------------------------------- Comando

    // RemoteMessage: remote_configure 1 {code1 1, device_info 2 {model 1, vendor 2, unknown1 3, unknown2 4,
    // package_name 5, app_version 6}}, remote_set_active 2 {active 1}, remote_error 3, remote_ping_request 8 {val1 1},
    // remote_ping_response 9 {val1 1}, remote_key_inject 10 {key_code 1, direction 2 (1 início, 2 fim, 3 curto)},
    // remote_ime_key_inject 20 {app_info 1 {app_package 12}, text_field_status 2},
    // remote_ime_batch_edit 21 {ime_counter 1, field_counter 2, edit_info 3 {insert 1, text_field_status 2 {start 1,
    // end 2, value 3}}}, remote_ime_show_request 22, remote_start 40 {started 1},
    // remote_set_volume_level 50 {player_model 3, volume_max 6, volume_level 7, volume_muted 8},
    // remote_app_link_launch_request 90 {app_link 1}.
    static W deviceInfo(String model, String vendor, String pkg) {
        return new W().string(1, model).string(2, vendor).varint(3, 1).string(4, "1").string(5, pkg).string(6, "1.0");
    }

    static final Map<String, Integer> KEYS = new LinkedHashMap<>();
    static {
        Object[] k = {"HOME", 3, "BACK", 4, "DPAD_UP", 19, "DPAD_DOWN", 20, "DPAD_LEFT", 21, "DPAD_RIGHT", 22,
            "DPAD_CENTER", 23, "VOLUME_UP", 24, "VOLUME_DOWN", 25, "POWER", 26, "MENU", 82, "SEARCH", 84,
            "MEDIA_PLAY_PAUSE", 85, "MEDIA_NEXT", 87, "MEDIA_PREVIOUS", 88, "MEDIA_REWIND", 89,
            "MEDIA_FAST_FORWARD", 90, "MUTE", 164, "INFO", 165, "CHANNEL_UP", 166, "CHANNEL_DOWN", 167, "GUIDE", 172,
            "CAPTIONS", 175, "SETTINGS", 176, "TV_INPUT", 178, "DEL", 67};
        for (int i = 0; i < k.length; i += 2) KEYS.put((String) k[i], (Integer) k[i + 1]);
    }

    static String keyName(long code) {
        for (var e : KEYS.entrySet()) if (e.getValue() == code) return e.getKey();
        return Long.toString(code);
    }

    // ---------------------------------------------------------------- Identidade e TLS

    static final class Identity {
        final PrivateKey key;
        final X509Certificate cert;
        Identity(PrivateKey key, X509Certificate cert) { this.key = key; this.cert = cert; }

        static Identity load(Path dir, String name) throws Exception {
            Path file = dir.resolve(name + ".p12");
            char[] pw = "atv".toCharArray();
            KeyStore ks = KeyStore.getInstance("PKCS12");
            if (Files.exists(file)) {
                try (InputStream in = Files.newInputStream(file)) { ks.load(in, pw); }
                return new Identity((PrivateKey) ks.getKey("me", pw), (X509Certificate) ks.getCertificate("me"));
            }
            Identity id = generate(name);
            ks.load(null, pw);
            ks.setKeyEntry("me", id.key, pw, new java.security.cert.Certificate[] {id.cert});
            Files.createDirectories(dir);
            try (OutputStream out = Files.newOutputStream(file)) { ks.store(out, pw); }
            return id;
        }

        /** Chave RSA de 2048 bits e certificado auto-assinado (o mesmo que a app faz no telemóvel). */
        static Identity generate(String cn) throws Exception {
            KeyPairGenerator g = KeyPairGenerator.getInstance("RSA");
            g.initialize(2048);
            KeyPair kp = g.generateKeyPair();
            long now = System.currentTimeMillis();
            byte[] name = der(0x30, der(0x31, der(0x30, cat(oid(2, 5, 4, 3), der(0x0C, cn.getBytes(StandardCharsets.UTF_8))))));
            byte[] alg = der(0x30, cat(oid(1, 2, 840, 113549, 1, 1, 11), new byte[] {5, 0}));
            byte[] tbs = der(0x30, cat(der(0xA0, der(0x02, new byte[] {2})),
                der(0x02, new BigInteger(63, new SecureRandom()).add(BigInteger.ONE).toByteArray()),
                alg, name, der(0x30, cat(time(now - 86_400_000L), time(now + 20L * 365 * 86_400_000L))), name,
                kp.getPublic().getEncoded()));
            Signature s = Signature.getInstance("SHA256withRSA");
            s.initSign(kp.getPrivate());
            s.update(tbs);
            byte[] cert = der(0x30, cat(tbs, alg, der(0x03, cat(new byte[] {0}, s.sign()))));
            return new Identity(kp.getPrivate(), (X509Certificate) CertificateFactory.getInstance("X.509")
                .generateCertificate(new ByteArrayInputStream(cert)));
        }

        SSLContext context() throws Exception {
            KeyStore ks = KeyStore.getInstance("PKCS12");
            ks.load(null, null);
            ks.setKeyEntry("me", key, "x".toCharArray(), new java.security.cert.Certificate[] {cert});
            KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
            kmf.init(ks, "x".toCharArray());
            SSLContext ctx = SSLContext.getInstance("TLS");
            // As duas pontas usam certificados auto-assinados: aceita-se qualquer um (o emparelhamento é que conta).
            ctx.init(kmf.getKeyManagers(), new TrustManager[] {new X509TrustManager() {
                public void checkClientTrusted(X509Certificate[] c, String a) {}
                public void checkServerTrusted(X509Certificate[] c, String a) {}
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            }}, new SecureRandom());
            return ctx;
        }
    }

    static byte[] cat(byte[]... parts) {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        for (byte[] p : parts) o.writeBytes(p);
        return o.toByteArray();
    }

    static byte[] der(int tag, byte[] c) {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        o.write(tag);
        int n = c.length;
        if (n < 0x80) o.write(n);
        else if (n < 0x100) { o.write(0x81); o.write(n); }
        else if (n < 0x10000) { o.write(0x82); o.write(n >> 8); o.write(n & 0xFF); }
        else { o.write(0x83); o.write(n >> 16); o.write((n >> 8) & 0xFF); o.write(n & 0xFF); }
        o.writeBytes(c);
        return o.toByteArray();
    }

    static byte[] oid(int... parts) {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        o.write(parts[0] * 40 + parts[1]);
        for (int i = 2; i < parts.length; i++) {
            int v = parts[i];
            Deque<Integer> chunks = new ArrayDeque<>();
            do { chunks.push(v & 0x7F); v >>>= 7; } while (v != 0);
            while (!chunks.isEmpty()) { int c = chunks.pop(); o.write(chunks.isEmpty() ? c : c | 0x80); }
        }
        return der(0x06, o.toByteArray());
    }

    static byte[] time(long ms) {
        SimpleDateFormat f = new SimpleDateFormat("yyMMddHHmmss'Z'", Locale.US);
        f.setTimeZone(TimeZone.getTimeZone("UTC"));
        return der(0x17, f.format(new Date(ms)).getBytes(StandardCharsets.US_ASCII));
    }

    static String fingerprint(java.security.cert.Certificate c) throws Exception {
        return hex(MessageDigest.getInstance("SHA-256").digest(c.getEncoded()));
    }

    // ---------------------------------------------------------------- Cliente (para testar contra uma TV a sério)

    static final class Client {
        static SSLSocket connect(String host, int port, Identity id) throws Exception {
            SSLSocket s = (SSLSocket) id.context().getSocketFactory().createSocket();
            s.connect(new InetSocketAddress(host, port), 5000);
            s.setSoTimeout(30_000);
            s.startHandshake();
            return s;
        }

        static void pair(String host, Path dir) throws Exception {
            Identity id = Identity.load(dir, "client");
            Path codeFile = dir.resolve("code.txt");
            Files.deleteIfExists(codeFile);
            try (SSLSocket s = connect(host, PAIRING_PORT, id)) {
                RSAPublicKey server = (RSAPublicKey) s.getSession().getPeerCertificates()[0].getPublicKey();
                InputStream in = s.getInputStream();
                OutputStream out = s.getOutputStream();
                send(out, pmsg(200, 10, new W().string(1, "atvremote").string(2, "GoatRemote")));
                expect(in, 11);
                send(out, pmsg(200, 20, new W().msg(1, hexEncoding()).varint(3, 1)));
                expect(in, 20);
                send(out, pmsg(200, 30, new W().msg(1, hexEncoding()).varint(2, 1)));
                expect(in, 31);
                System.out.println("A TV mostra o código: escreve-o em " + codeFile);
                long until = System.currentTimeMillis() + 120_000;
                while (!Files.exists(codeFile) && System.currentTimeMillis() < until) Thread.sleep(300);
                String code = Files.readString(codeFile).trim().toUpperCase();
                byte[] alpha = secret((RSAPublicKey) id.cert.getPublicKey(), server, unhex(code.substring(2)));
                if ((alpha[0] & 0xFF) != Integer.parseInt(code.substring(0, 2), 16)) {
                    System.out.println("O código não bate certo com os certificados (primeiro byte " + String.format("%02X", alpha[0]) + ")");
                }
                send(out, pmsg(200, 40, new W().bytes(1, alpha)));
                M ack = M.parse(read(in));
                System.out.println(ack.num(2) == 200 && ack.has(41) ? "Emparelhado" : "Recusado: estado " + ack.num(2));
            }
        }

        static M expect(InputStream in, int field) throws IOException {
            M m = M.parse(read(in));
            if (m.num(2) != 200 || !m.has(field)) throw new IOException("Esperava " + field + ", veio " + m + " (estado " + m.num(2) + ")");
            return m;
        }

        /** Liga ao comando e faz a negociação; devolve o estado que a TV contou entretanto. */
        static Map<String, String> open(SSLSocket s) throws Exception {
            Map<String, String> st = new LinkedHashMap<>();
            InputStream in = s.getInputStream();
            OutputStream out = s.getOutputStream();
            boolean active = false;
            long features = FEATURES;
            long until = System.currentTimeMillis() + 4000;
            s.setSoTimeout(1500);
            while (System.currentTimeMillis() < until) {
                M m;
                try { m = M.parse(read(in)); } catch (SocketTimeoutException e) { if (active) break; else continue; }
                if (m.has(1)) {
                    long supported = m.msg(1).num(1);
                    st.put("features", Long.toString(supported));
                    st.put("tv", m.msg(1).msg(2).str(1) + " / " + m.msg(1).msg(2).str(2));
                    features = FEATURES & supported;
                    send(out, new W().msg(1, new W().varint(1, features).msg(2, deviceInfo("GoatRemote", "GOAT", "cc.slokker.goatremote"))).done());
                } else if (m.has(2)) {
                    send(out, new W().msg(2, new W().varint(1, features)).done());
                    active = true;
                } else if (m.has(8)) {
                    send(out, new W().msg(9, new W().varint(1, m.msg(8).num(1))).done());
                } else if (m.has(40)) {
                    st.put("ligada", Boolean.toString(m.msg(40).num(1) != 0));
                } else if (m.has(50)) {
                    M v = m.msg(50);
                    st.put("volume", v.num(7) + "/" + v.num(6) + (v.num(8) != 0 ? " (sem som)" : "") + " " + v.str(3));
                } else if (m.has(20)) {
                    st.put("app", m.msg(20).msg(1).str(12));
                } else if (m.has(21)) {
                    st.put("ime", m.msg(21).num(1) + "/" + m.msg(21).num(2));
                } else if (m.has(3)) {
                    st.put("erro", m.msg(3).toString());
                }
            }
            return st;
        }

        static void keys(String host, Path dir, List<String> keys) throws Exception {
            try (SSLSocket s = connect(host, REMOTE_PORT, Identity.load(dir, "client"))) {
                open(s);
                OutputStream out = s.getOutputStream();
                for (String k : keys) {
                    boolean hold = k.startsWith("long:");
                    String name = hold ? k.substring(5) : k;
                    int code = KEYS.containsKey(name) ? KEYS.get(name) : Integer.parseInt(name);
                    if (hold) {
                        send(out, new W().msg(10, new W().varint(1, code).varint(2, 1)).done());
                        Thread.sleep(1000);
                        send(out, new W().msg(10, new W().varint(1, code).varint(2, 2)).done());
                    } else {
                        send(out, new W().msg(10, new W().varint(1, code).varint(2, 3)).done());
                    }
                    Thread.sleep(250);
                }
                System.out.println("Enviadas: " + keys);
            }
        }

        static void text(String host, String text, Path dir) throws Exception {
            try (SSLSocket s = connect(host, REMOTE_PORT, Identity.load(dir, "client"))) {
                Map<String, String> st = open(s);
                String[] ime = st.getOrDefault("ime", "0/0").split("/");
                send(s.getOutputStream(), imeText(Integer.parseInt(ime[0]), Integer.parseInt(ime[1]), text));
                Thread.sleep(500);
                System.out.println("Texto enviado (ime " + st.getOrDefault("ime", "sem campo aberto") + ")");
            }
        }

        static void app(String host, String link, Path dir) throws Exception {
            try (SSLSocket s = connect(host, REMOTE_PORT, Identity.load(dir, "client"))) {
                open(s);
                send(s.getOutputStream(), new W().msg(90, new W().string(1, link)).done());
                Thread.sleep(500);
                System.out.println("Aberto: " + link);
            }
        }

        static void status(String host, Path dir) throws Exception {
            try (SSLSocket s = connect(host, REMOTE_PORT, Identity.load(dir, "client"))) {
                open(s).forEach((k, v) -> System.out.println(k + ": " + v));
            }
        }
    }

    static byte[] imeText(int imeCounter, int fieldCounter, String text) {
        int end = Math.max(text.codePointCount(0, text.length()) - 1, 0);
        W status = new W().varint(1, end).varint(2, end).string(3, text);
        return new W().msg(21, new W().varint(1, imeCounter).varint(2, fieldCounter)
            .msg(3, new W().varint(1, 1).msg(2, status))).done();
    }

    // ---------------------------------------------------------------- A TV falsa (para os testes no CI)

    static final class FakeTv {
        final Identity id;
        final Path dir;
        final Set<String> paired = ConcurrentHashMap.newKeySet();
        final List<String> log = new CopyOnWriteArrayList<>();
        volatile String code = "";
        volatile boolean on = true;
        volatile int volume = 20;
        volatile boolean muted = false;
        volatile String app = "com.google.android.youtube.tv";
        int imeCounter = 1, fieldCounter = 1;

        FakeTv(Path dir) throws Exception {
            this.dir = dir;
            this.id = Identity.load(dir, "tv");
        }

        void run() throws Exception {
            SSLServerSocketFactory f = id.context().getServerSocketFactory();
            SSLServerSocket pairing = (SSLServerSocket) f.createServerSocket(PAIRING_PORT);
            SSLServerSocket remote = (SSLServerSocket) f.createServerSocket(REMOTE_PORT);
            pairing.setNeedClientAuth(true);
            remote.setNeedClientAuth(true);
            control();
            System.out.println("TV falsa: emparelhamento :" + PAIRING_PORT + ", comando :" + REMOTE_PORT + ", controlo 127.0.0.1:" + CONTROL_PORT);
            Thread.ofPlatform().start(() -> accept(pairing, this::pairing));
            accept(remote, this::remote);
        }

        interface Handler { void handle(SSLSocket s) throws Exception; }

        void accept(SSLServerSocket server, Handler h) {
            while (true) {
                try {
                    SSLSocket s = (SSLSocket) server.accept();
                    Thread.ofPlatform().start(() -> {
                        try (s) { s.startHandshake(); h.handle(s); }
                        catch (EOFException | SocketException e) { /* o cliente fechou */ }
                        catch (Exception e) { note("erro: " + e); }
                    });
                } catch (IOException e) { note("accept: " + e); }
            }
        }

        void note(String line) { System.out.println(line); log.add(line); }

        void pairing(SSLSocket s) throws Exception {
            java.security.cert.Certificate peer = s.getSession().getPeerCertificates()[0];
            RSAPublicKey client = (RSAPublicKey) peer.getPublicKey();
            InputStream in = s.getInputStream();
            OutputStream out = s.getOutputStream();
            byte[] expected = null;
            while (true) {
                M m = M.parse(read(in));
                if (m.has(10)) {
                    note("pairing_request " + m.msg(10).str(2));
                    send(out, pmsg(200, 11, new W().string(1, "Fake TV")));
                } else if (m.has(20)) {
                    send(out, pmsg(200, 20, new W().msg(1, hexEncoding()).varint(3, 1)));
                } else if (m.has(30)) {
                    send(out, pmsg(200, 31, new W()));
                    byte[] tail = new byte[2];
                    new SecureRandom().nextBytes(tail);
                    expected = secret(client, (RSAPublicKey) id.cert.getPublicKey(), tail);
                    code = String.format("%02X", expected[0]) + hex(tail);
                    note("código no ecrã: " + code);
                } else if (m.has(40)) {
                    boolean ok = expected != null && Arrays.equals(expected, m.msg(40).raw(1));
                    code = "";
                    if (ok) {
                        paired.add(fingerprint(peer));
                        note("emparelhado");
                        send(out, pmsg(200, 41, new W().bytes(1, expected)));
                    } else {
                        note("segredo errado");
                        send(out, new W().varint(1, 2).varint(2, 402).done());
                    }
                    return;
                }
            }
        }

        void remote(SSLSocket s) throws Exception {
            if (!paired.contains(fingerprint(s.getSession().getPeerCertificates()[0]))) {
                note("comando recusado: telemóvel não emparelhado");
                return;
            }
            InputStream in = s.getInputStream();
            OutputStream out = s.getOutputStream();
            send(out, new W().msg(1, new W().varint(1, 622).msg(2, deviceInfo("Fake TV", "GOAT", "fake"))).done());
            note("ligado ao comando");
            ScheduledExecutorService ping = Executors.newSingleThreadScheduledExecutor();
            ping.scheduleAtFixedRate(() -> {
                try { send(out, new W().msg(8, new W().varint(1, System.currentTimeMillis() % 100000)).done()); } catch (IOException ignored) {}
            }, 5, 5, TimeUnit.SECONDS);
            try {
                while (true) {
                    M m = M.parse(read(in));
                    if (m.has(1)) {
                        note("configure " + m.msg(1).num(1) + " " + m.msg(1).msg(2).str(1));
                        send(out, new W().msg(2, new W().varint(1, 622)).done());
                    } else if (m.has(2)) {
                        send(out, new W().msg(40, new W().varint(1, on ? 1 : 0)).done());
                        sendVolume(out);
                        sendApp(out);
                    } else if (m.has(10)) {
                        M k = m.msg(10);
                        String name = keyName(k.num(1));
                        long dir = k.num(2);
                        note("tecla " + name + (dir == 1 ? " (início)" : dir == 2 ? " (fim)" : ""));
                        if (dir == 3 || dir == 1) react(out, name);
                    } else if (m.has(21)) {
                        for (M e : m.msg(21).msgs(3)) note("texto " + e.msg(2).str(3));
                    } else if (m.has(90)) {
                        String link = m.msg(90).str(1);
                        note("abrir " + link);
                        app = link.replaceAll("^[a-z]+://", "").split("[/?]")[0];
                        sendApp(out);
                    } else if (m.has(9)) {
                        // resposta ao ping
                    } else {
                        note("mensagem " + m);
                    }
                }
            } finally {
                ping.shutdownNow();
            }
        }

        void react(OutputStream out, String key) throws IOException {
            switch (key) {
                case "VOLUME_UP" -> { volume = Math.min(100, volume + 5); muted = false; sendVolume(out); }
                case "VOLUME_DOWN" -> { volume = Math.max(0, volume - 5); sendVolume(out); }
                case "MUTE" -> { muted = !muted; sendVolume(out); }
                case "POWER" -> { on = !on; send(out, new W().msg(40, new W().varint(1, on ? 1 : 0)).done()); }
                case "HOME" -> { app = "com.google.android.tvlauncher"; sendApp(out); }
                default -> {}
            }
        }

        void sendVolume(OutputStream out) throws IOException {
            send(out, new W().msg(50, new W().string(3, "Fake TV").varint(6, 100).varint(7, volume).varint(8, muted ? 1 : 0)).done());
        }

        void sendApp(OutputStream out) throws IOException {
            send(out, new W().msg(20, new W().msg(1, new W().string(12, app))).done());
            send(out, new W().msg(21, new W().varint(1, ++imeCounter).varint(2, ++fieldCounter)).done());
        }

        /** 127.0.0.1:7000: /code, /log e /state, em texto simples, para os testes lerem. */
        void control() throws IOException {
            ServerSocket http = new ServerSocket(CONTROL_PORT, 50, InetAddress.getLoopbackAddress());
            Thread.ofPlatform().daemon().start(() -> {
                while (true) {
                    try (Socket c = http.accept()) {
                        BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(), StandardCharsets.UTF_8));
                        String line = r.readLine();
                        String path = line == null ? "/" : line.split(" ")[1];
                        String body = switch (path) {
                            case "/code" -> code;
                            case "/log" -> String.join("\n", log);
                            case "/state" -> "on=" + on + "\nvolume=" + volume + "\nmuted=" + muted + "\napp=" + app;
                            default -> "code log state";
                        };
                        byte[] b = body.getBytes(StandardCharsets.UTF_8);
                        OutputStream o = c.getOutputStream();
                        o.write(("HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: " + b.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
                        o.write(b);
                    } catch (Exception ignored) {}
                }
            });
        }
    }
}
