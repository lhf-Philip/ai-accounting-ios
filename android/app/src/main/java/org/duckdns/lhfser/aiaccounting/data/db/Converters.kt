package org.duckdns.lhfser.aiaccounting.data.db

import androidx.room.TypeConverter
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

class Converters {
    @TypeConverter
    fun fromUUID(value: UUID?): String? = value?.toString()

    @TypeConverter
    fun toUUID(value: String?): UUID? = value?.let(UUID::fromString)

    @TypeConverter
    fun fromInstant(value: Instant?): Long? = value?.toEpochMilli()

    @TypeConverter
    fun toInstant(value: Long?): Instant? = value?.let(Instant::ofEpochMilli)

    @TypeConverter
    fun fromBigDecimal(value: BigDecimal?): String? = value?.toPlainString()

    @TypeConverter
    fun toBigDecimal(value: String?): BigDecimal? = value?.let { BigDecimal(it) }

    @TypeConverter
    fun fromAccountType(value: AccountType?): String? = value?.rawValue

    @TypeConverter
    fun toAccountType(value: String?): AccountType? =
        value?.let { raw -> AccountType.entries.firstOrNull { it.rawValue == raw } }

    @TypeConverter
    fun fromTransactionType(value: TransactionType?): String? = value?.rawValue

    @TypeConverter
    fun toTransactionType(value: String?): TransactionType? =
        value?.let { raw -> TransactionType.entries.firstOrNull { it.rawValue == raw } }

    @TypeConverter
    fun fromTransferSide(value: TransferSide?): String? = value?.rawValue

    @TypeConverter
    fun toTransferSide(value: String?): TransferSide? =
        value?.let { raw -> TransferSide.entries.firstOrNull { it.rawValue == raw } }

    @TypeConverter
    fun fromCategoryKind(value: CategoryKind?): String? = value?.rawValue

    @TypeConverter
    fun toCategoryKind(value: String?): CategoryKind? =
        value?.let { raw -> CategoryKind.entries.firstOrNull { it.rawValue == raw } }
}
