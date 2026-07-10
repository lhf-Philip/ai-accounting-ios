package org.duckdns.lhfser.aiaccounting.core.advance

import java.math.BigDecimal
import java.util.UUID

enum class AdvanceSettlementDirection {
    IAdvancedOthers,
    OthersAdvancedMe
}

enum class AdvanceEntryRole {
    SelfExpense,
    InitialAsset,
    InitialDebt,
    RepaymentAsset,
    RepaymentDebt
}

sealed interface AdvanceRepaymentRecordKind {
    data object Ordinary : AdvanceRepaymentRecordKind
    data class MutualDebtOffset(val id: UUID) : AdvanceRepaymentRecordKind
    data class ManualDebtSettlement(val id: UUID) : AdvanceRepaymentRecordKind
    data object InvalidSpecial : AdvanceRepaymentRecordKind
}

object AdvanceSemantics {
    const val MutualDebtOffsetMarkerPrefix = "[債務抵銷:"
    const val ManualDebtSettlementMarkerPrefix = "[跨幣種平賬:"

    fun totalAdvanced(
        myShareAmount: BigDecimal,
        participantOwedAmounts: List<BigDecimal>
    ): BigDecimal = participantOwedAmounts.fold(myShareAmount, BigDecimal::add)

    fun outstanding(participantRemainingAmounts: List<BigDecimal>): BigDecimal {
        return participantRemainingAmounts.fold(BigDecimal.ZERO, BigDecimal::add)
    }

    fun settlementDirection(
        debtAccountId: UUID?,
        outgoingAccountId: UUID?,
        outgoingNote: String
    ): AdvanceSettlementDirection {
        if (debtAccountId != null && outgoingAccountId == debtAccountId) {
            return AdvanceSettlementDirection.OthersAdvancedMe
        }
        val compactedNote = outgoingNote.replace(" ", "")
        return if (
            compactedNote.contains("(代墊給我") || compactedNote.contains("(他人代墊我")
        ) {
            AdvanceSettlementDirection.OthersAdvancedMe
        } else {
            AdvanceSettlementDirection.IAdvancedOthers
        }
    }

    fun isMutualDebtOffset(note: String): Boolean {
        return note.trim().startsWith(MutualDebtOffsetMarkerPrefix)
    }

    fun mutualDebtOffsetMarker(id: UUID): String = "$MutualDebtOffsetMarkerPrefix$id]"

    fun mutualDebtOffsetId(note: String): UUID? {
        return markerId(note, MutualDebtOffsetMarkerPrefix)
    }

    fun isManualDebtSettlement(note: String): Boolean {
        return note.trim().startsWith(ManualDebtSettlementMarkerPrefix)
    }

    fun manualDebtSettlementMarker(id: UUID): String = "$ManualDebtSettlementMarkerPrefix$id]"

    fun manualDebtSettlementId(note: String): UUID? {
        return markerId(note, ManualDebtSettlementMarkerPrefix)
    }

    fun repaymentRecordKind(note: String): AdvanceRepaymentRecordKind {
        mutualDebtOffsetId(note)?.let {
            return AdvanceRepaymentRecordKind.MutualDebtOffset(it)
        }
        if (isMutualDebtOffset(note)) return AdvanceRepaymentRecordKind.InvalidSpecial
        manualDebtSettlementId(note)?.let {
            return AdvanceRepaymentRecordKind.ManualDebtSettlement(it)
        }
        if (isManualDebtSettlement(note)) return AdvanceRepaymentRecordKind.InvalidSpecial
        return AdvanceRepaymentRecordKind.Ordinary
    }

    private fun markerId(note: String, prefix: String): UUID? {
        val trimmed = note.trim()
        if (!trimmed.startsWith(prefix)) return null
        val end = trimmed.indexOf(']')
        if (end <= prefix.length) return null
        return runCatching {
            UUID.fromString(trimmed.substring(prefix.length, end))
        }.getOrNull()
    }
}
