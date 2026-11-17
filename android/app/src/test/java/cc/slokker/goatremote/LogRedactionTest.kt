package cc.slokker.goatremote

import cc.slokker.goatremote.Contracts.objects
import cc.slokker.goatremote.data.LogRedaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** O registo de diagnóstico sem credenciais nem endereços: as mesmas linhas de contracts/redaction.json que o iPhone testa. */
class LogRedactionTest {
    @Test
    fun contractRows() {
        val wrong = Contracts.obj("redaction.json").getJSONArray("rows").objects().mapNotNull { row ->
            val got = LogRedaction.redact(row.getString("input"))
            if (got == row.getString("output")) null else "${row.getString("input")}\n  want ${row.getString("output")}\n  got  $got"
        }
        assertEquals(wrong.joinToString("\n"), 0, wrong.size)
    }

    @Test
    fun namesAreKeptAcrossTheWholeReport() {
        val log = "Found Sala at 192.168.1.20:6466\nFound Quarto at 192.168.1.21:6466\nConnecting to Sala (192.168.1.20:6466)"
        assertEquals("Found Sala at ip1:6466\nFound Quarto at ip2:6466\nConnecting to Sala (ip1:6466)", LogRedaction.redact(log))
    }

    @Test
    fun knownSecretsGoToo() {
        val out = LogRedaction.redact("Error with tok_live_999 and ab", listOf("tok_live_999", "ab"))
        assertFalse(out, out.contains("tok_live_999"))
        // Segredos de menos de 3 caracteres não se trocam (senão apagava letras soltas).
        assertEquals("Error with *** and ab", out)
    }
}
