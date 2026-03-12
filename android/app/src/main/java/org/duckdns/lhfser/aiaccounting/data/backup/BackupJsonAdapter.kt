package org.duckdns.lhfser.aiaccounting.data.backup

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.TypeAdapter
import com.google.gson.stream.JsonReader
import com.google.gson.stream.JsonToken
import com.google.gson.stream.JsonWriter
import java.math.BigDecimal
import java.time.Instant
import java.time.format.DateTimeFormatter

object BackupJsonAdapter {
    private val instantFormatter = DateTimeFormatter.ISO_INSTANT

    private val instantAdapter = object : TypeAdapter<Instant>() {
        override fun write(out: JsonWriter, value: Instant?) {
            if (value == null) {
                out.nullValue()
            } else {
                out.value(instantFormatter.format(value))
            }
        }

        override fun read(reader: JsonReader): Instant? {
            return when (reader.peek()) {
                JsonToken.NULL -> {
                    reader.nextNull(); null
                }
                JsonToken.STRING -> Instant.parse(reader.nextString())
                else -> {
                    val raw = reader.nextString()
                    Instant.parse(raw)
                }
            }
        }
    }

    private val bigDecimalAdapter = object : TypeAdapter<BigDecimal>() {
        override fun write(out: JsonWriter, value: BigDecimal?) {
            if (value == null) {
                out.nullValue()
            } else {
                out.value(value)
            }
        }

        override fun read(reader: JsonReader): BigDecimal? {
            return when (reader.peek()) {
                JsonToken.NULL -> {
                    reader.nextNull(); null
                }
                JsonToken.STRING -> reader.nextString().toBigDecimalOrNull()
                JsonToken.NUMBER -> reader.nextString().toBigDecimalOrNull()
                else -> reader.nextString().toBigDecimalOrNull()
            }
        }
    }

    val gson: Gson = GsonBuilder()
        .registerTypeAdapter(Instant::class.java, instantAdapter)
        .registerTypeAdapter(BigDecimal::class.java, bigDecimalAdapter)
        .create()
}
