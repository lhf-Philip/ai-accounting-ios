package org.duckdns.lhfser.aiaccounting.core.advance

import org.duckdns.lhfser.aiaccounting.core.model.AdvanceParticipant
import java.math.BigDecimal
import java.math.RoundingMode

data class ParticipantProgress(
    val name: String,
    val owedAmount: BigDecimal,
    val repaidAmount: BigDecimal,
    val remainingAmount: BigDecimal
)

data class AdvanceProgress(
    val participants: List<ParticipantProgress>,
    val outstandingTotal: BigDecimal
)

object AdvanceProgressCalculator {
    fun compute(participants: List<AdvanceParticipant>): AdvanceProgress {
        val progressList = participants.map { participant ->
            val remaining = (participant.owedAmount - participant.repaidAmount)
                .max(BigDecimal.ZERO)
                .setScale(2, RoundingMode.HALF_UP)

            ParticipantProgress(
                name = participant.name,
                owedAmount = participant.owedAmount.setScale(2, RoundingMode.HALF_UP),
                repaidAmount = participant.repaidAmount.setScale(2, RoundingMode.HALF_UP),
                remainingAmount = remaining
            )
        }

        val total = progressList
            .fold(BigDecimal.ZERO) { acc, row -> acc + row.remainingAmount }
            .setScale(2, RoundingMode.HALF_UP)

        return AdvanceProgress(participants = progressList, outstandingTotal = total)
    }
}
