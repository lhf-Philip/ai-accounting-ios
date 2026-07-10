import Foundation
import SwiftData

@MainActor
enum AdvanceMaintenance {
    struct LegacyLinkRepairResult {
        let updatedCaseLinkCount: Int
        let unresolvedCaseLinkCount: Int
        let updatedParticipantLinkCount: Int
        let unresolvedParticipantLinkCount: Int

        var totalUpdated: Int {
            updatedCaseLinkCount + updatedParticipantLinkCount
        }

        var totalUnresolved: Int {
            unresolvedCaseLinkCount + unresolvedParticipantLinkCount
        }
    }

    struct ExplicitLinkBackfillResult {
        let linkedTransactionCount: Int
        let updatedCaseCount: Int
        let unresolvedRecordCount: Int
    }

    struct LegacyBorrowedAdvanceRepairResult {
        let repairedParticipantCount: Int
        let removedInflatedAccountTransactionCount: Int
    }

    struct RepaymentReconciliationResult {
        let checkedParticipantCount: Int
        let updatedParticipantCount: Int
    }

    private static let roundingTolerance = Decimal(string: "0.0001") ?? 0.0001

    static func reconcileUnderstatedRepaymentTotals(
        modelContext: ModelContext
    ) throws -> RepaymentReconciliationResult {
        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
        let groupedTotals = Dictionary(grouping: repayments.compactMap { repayment -> (UUID, Decimal)? in
            guard let participantID = repayment.participant?.id,
                  repayment.normalizedAmount > 0 else {
                return nil
            }
            return (participantID, repayment.normalizedAmount)
        }, by: \.0)
        .mapValues { entries in
            entries.reduce(Decimal.zero) { $0 + $1.1 }
        }

        guard !groupedTotals.isEmpty else {
            return RepaymentReconciliationResult(
                checkedParticipantCount: 0,
                updatedParticipantCount: 0
            )
        }

        let participants = try modelContext.fetch(FetchDescriptor<AdvanceParticipant>())
        var updatedCount = 0
        for participant in participants {
            guard let recordedTotal = groupedTotals[participant.id] else { continue }
            let expectedTotal = min(recordedTotal, participant.owedAmount)
            guard expectedTotal - participant.repaidAmount > roundingTolerance else { continue }
            participant.repaidAmount = expectedTotal
            participant.updatedAt = Date()
            participant.advanceCase?.updatedAt = Date()
            updatedCount += 1
        }

        if updatedCount > 0 {
            try modelContext.save()
        }
        return RepaymentReconciliationResult(
            checkedParticipantCount: groupedTotals.count,
            updatedParticipantCount: updatedCount
        )
    }
    static func repairLegacyBorrowedAdvanceAccountInflation(modelContext: ModelContext) throws -> LegacyBorrowedAdvanceRepairResult {
        let participants = try modelContext.fetch(FetchDescriptor<AdvanceParticipant>())
        var repairedParticipantCount = 0
        var removedInflatedAccountTransactionCount = 0
        var repairedExpenseTransactions: [FinancialTransaction] = []

        for participant in participants {
            guard let groupID = participant.initialTransferGroupID,
                  let debtAccount = participant.debtAccount,
                  let advanceCase = participant.advanceCase
            else { continue }

            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            let group = try modelContext.fetch(descriptor)
            guard let outgoing = group.first(where: { tx in
                tx.account?.id == debtAccount.id && (tx.transferSide == .outgoing || tx.amount < 0)
            }) else { continue }

            let inflatedIncoming = group.filter { tx in
                tx.id != outgoing.id &&
                    tx.amount > 0 &&
                    tx.account?.type != .debt
            }
            guard !inflatedIncoming.isEmpty else { continue }

            outgoing.type = .expense
            outgoing.amount = -abs(outgoing.amount)
            outgoing.linkedTransactionID = nil
            outgoing.transferSide = .outgoing
            outgoing.category = advanceCase.expenseCategory
            outgoing.note = "\(advanceCase.note.isEmpty ? advanceCase.title : advanceCase.note) (他人代墊我：\(debtAccount.name))"
            outgoing.updatedAt = Date()
            repairedExpenseTransactions.append(outgoing)

            for tx in inflatedIncoming {
                modelContext.delete(tx)
                removedInflatedAccountTransactionCount += 1
            }

            advanceCase.payerAccount = nil
            advanceCase.updatedAt = Date()
            participant.updatedAt = Date()
            repairedParticipantCount += 1
        }

        try modelContext.save()
        try BudgetHistoryService.shared.syncAffected(
            by: repairedExpenseTransactions,
            modelContext: modelContext,
            currencyService: CurrencyService.shared
        )

        return LegacyBorrowedAdvanceRepairResult(
            repairedParticipantCount: repairedParticipantCount,
            removedInflatedAccountTransactionCount: removedInflatedAccountTransactionCount
        )
    }
    static func repairLegacyLinks(modelContext: ModelContext) throws -> LegacyLinkRepairResult {
        let advanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())
        let participants = try modelContext.fetch(FetchDescriptor<AdvanceParticipant>())
        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())

        var updatedCaseLinkCount = 0
        var unresolvedCaseLinkCount = 0
        var updatedParticipantLinkCount = 0
        var unresolvedParticipantLinkCount = 0

        let groupedTransfers = Dictionary(
            grouping: transactions.filter { $0.type == .transfer && $0.transferGroupID != nil }
        ) { $0.transferGroupID! }

        var usedExpenseIDs = Set<UUID>(advanceCases.compactMap(\.selfExpenseTransactionID))
        var usedGroupIDs = Set<UUID>(participants.compactMap(\.initialTransferGroupID))
        usedGroupIDs.formUnion(repayments.compactMap(\.linkedTransferGroupID))

        let now = Date()
        let calendar = Calendar.current

        for advanceCase in advanceCases where advanceCase.myShareAmount > 0 && advanceCase.selfExpenseTransactionID == nil {
            guard let payerAccount = advanceCase.payerAccount else {
                unresolvedCaseLinkCount += 1
                continue
            }

            let targetAmount = -abs(advanceCase.myShareAmount)
            let candidates = transactions.filter { tx in
                tx.type == .expense
                    && tx.account?.id == payerAccount.id
                    && tx.currencyCode == advanceCase.currencyCode
                    && decimalEquals(tx.amount, targetAmount)
                    && calendar.isDate(tx.date, inSameDayAs: advanceCase.date)
                    && !usedExpenseIDs.contains(tx.id)
            }

            if let best = bestSelfExpenseCandidate(candidates, advanceCase: advanceCase) {
                advanceCase.selfExpenseTransactionID = best.id
                advanceCase.updatedAt = now
                usedExpenseIDs.insert(best.id)
                updatedCaseLinkCount += 1
            } else {
                unresolvedCaseLinkCount += 1
            }
        }

        for participant in participants where participant.initialTransferGroupID == nil {
            guard
                let advanceCase = participant.advanceCase,
                let payerAccount = advanceCase.payerAccount,
                let debtAccount = participant.debtAccount
            else {
                unresolvedParticipantLinkCount += 1
                continue
            }

            let targetOutgoing = -abs(participant.owedAmount)
            let targetIncoming = abs(participant.owedAmount)
            let participantName = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let payerName = payerAccount.name.trimmingCharacters(in: .whitespacesAndNewlines)

            var bestGroupID: UUID?
            var bestScore = Int.min
            var bestDateDiff = TimeInterval.greatestFiniteMagnitude

            for (groupID, group) in groupedTransfers {
                if usedGroupIDs.contains(groupID) {
                    continue
                }

                let outgoingCandidates = group.filter { tx in
                    tx.account?.id == payerAccount.id
                        && tx.currencyCode == advanceCase.currencyCode
                        && decimalEquals(tx.amount, targetOutgoing)
                }
                if outgoingCandidates.isEmpty {
                    continue
                }

                let incomingCandidates = group.filter { tx in
                    tx.account?.id == debtAccount.id
                        && tx.currencyCode == advanceCase.currencyCode
                        && decimalEquals(tx.amount, targetIncoming)
                }
                if incomingCandidates.isEmpty {
                    continue
                }

                let outgoingByDate = outgoingCandidates.sorted {
                    abs($0.date.timeIntervalSince(advanceCase.date)) < abs($1.date.timeIntervalSince(advanceCase.date))
                }
                let incomingByDate = incomingCandidates.sorted {
                    abs($0.date.timeIntervalSince(advanceCase.date)) < abs($1.date.timeIntervalSince(advanceCase.date))
                }

                guard let outgoing = outgoingByDate.first, let incoming = incomingByDate.first else {
                    continue
                }

                var score = 0
                if outgoing.note.contains("代墊") {
                    score += 2
                }
                if !participantName.isEmpty && outgoing.note.localizedCaseInsensitiveContains(participantName) {
                    score += 3
                }
                if !payerName.isEmpty && incoming.note.localizedCaseInsensitiveContains(payerName) {
                    score += 1
                }

                let outgoingDateDiff = abs(outgoing.date.timeIntervalSince(advanceCase.date))
                let incomingDateDiff = abs(incoming.date.timeIntervalSince(advanceCase.date))
                let dateDiff = min(outgoingDateDiff, incomingDateDiff)

                if outgoingDateDiff <= 5 * 60 {
                    score += 2
                } else if calendar.isDate(outgoing.date, inSameDayAs: advanceCase.date) {
                    score += 1
                }

                if incomingDateDiff <= 5 * 60 {
                    score += 1
                }

                if score > bestScore || (score == bestScore && dateDiff < bestDateDiff) {
                    bestScore = score
                    bestDateDiff = dateDiff
                    bestGroupID = groupID
                }
            }

            if let groupID = bestGroupID {
                participant.initialTransferGroupID = groupID
                participant.updatedAt = now
                advanceCase.updatedAt = now
                usedGroupIDs.insert(groupID)
                updatedParticipantLinkCount += 1
            } else {
                unresolvedParticipantLinkCount += 1
            }
        }

        if updatedCaseLinkCount > 0 || updatedParticipantLinkCount > 0 {
            try modelContext.save()
        }

        return LegacyLinkRepairResult(
            updatedCaseLinkCount: updatedCaseLinkCount,
            unresolvedCaseLinkCount: unresolvedCaseLinkCount,
            updatedParticipantLinkCount: updatedParticipantLinkCount,
            unresolvedParticipantLinkCount: unresolvedParticipantLinkCount
        )
    }

    static func backfillExplicitLinks(modelContext: ModelContext) throws -> ExplicitLinkBackfillResult {
        let advanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())
        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let transactionsByGroup = Dictionary(
            grouping: transactions.compactMap { transaction -> (UUID, FinancialTransaction)? in
                transaction.transferGroupID.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        var linkedTransactionCount = 0
        var updatedCaseCount = 0
        var unresolvedRecordCount = 0

        for advanceCase in advanceCases {
            if advanceCase.direction == nil {
                if let participant = advanceCase.participants.first {
                    advanceCase.direction = inferSettlementDirection(
                        for: participant,
                        modelContext: modelContext
                    ) == .iAdvancedOthers ? .iAdvancedOthers : .othersAdvancedMe
                    updatedCaseCount += 1
                } else {
                    unresolvedRecordCount += 1
                }
            }

            if (advanceCase.tagIDs ?? []).isEmpty,
               let expenseID = advanceCase.selfExpenseTransactionID,
               let expense = transactionByID[expenseID] {
                advanceCase.tagIDs = expense.tags.map(\.id)
                updatedCaseCount += 1
            }

            if let expenseID = advanceCase.selfExpenseTransactionID,
               let expense = transactionByID[expenseID] {
                if expense.advanceCaseID == nil {
                    expense.advanceCaseID = advanceCase.id
                    expense.advanceEntryRole = .selfExpense
                    linkedTransactionCount += 1
                }
            } else if advanceCase.myShareAmount > 0, advanceCase.direction == .iAdvancedOthers {
                unresolvedRecordCount += 1
            }

            for participant in advanceCase.participants {
                guard let groupID = participant.initialTransferGroupID,
                      let entries = transactionsByGroup[groupID],
                      !entries.isEmpty
                else {
                    unresolvedRecordCount += 1
                    continue
                }
                for entry in entries {
                    guard entry.advanceCaseID == nil else { continue }
                    entry.advanceCaseID = advanceCase.id
                    entry.advanceParticipantID = participant.id
                    entry.advanceEntryRole = entry.account?.type == .debt ? .initialDebt : .initialAsset
                    linkedTransactionCount += 1
                }
            }

            for repayment in advanceCase.repayments {
                guard let groupID = repayment.linkedTransferGroupID,
                      let entries = transactionsByGroup[groupID],
                      !entries.isEmpty
                else {
                    if AdvanceSemantics.repaymentRecordKind(note: repayment.note) == .ordinary {
                        unresolvedRecordCount += 1
                    }
                    continue
                }
                for entry in entries {
                    guard entry.advanceCaseID == nil else { continue }
                    entry.advanceCaseID = advanceCase.id
                    entry.advanceParticipantID = repayment.participant?.id
                    entry.advanceRepaymentID = repayment.id
                    entry.advanceEntryRole = entry.account?.type == .debt ? .repaymentDebt : .repaymentAsset
                    linkedTransactionCount += 1
                }
            }
        }

        if linkedTransactionCount > 0 || updatedCaseCount > 0 {
            try modelContext.save()
        }
        return ExplicitLinkBackfillResult(
            linkedTransactionCount: linkedTransactionCount,
            updatedCaseCount: updatedCaseCount,
            unresolvedRecordCount: unresolvedRecordCount
        )
    }

    private static func bestSelfExpenseCandidate(
        _ candidates: [FinancialTransaction],
        advanceCase: AdvanceCase
    ) -> FinancialTransaction? {
        guard !candidates.isEmpty else { return nil }

        let trimmedTitle = advanceCase.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = advanceCase.note.trimmingCharacters(in: .whitespacesAndNewlines)

        var bestCandidate: FinancialTransaction?
        var bestScore = Int.min
        var bestDateDiff = TimeInterval.greatestFiniteMagnitude

        for candidate in candidates {
            var score = 0

            if candidate.note.contains("自己份額") {
                score += 4
            }
            if !trimmedTitle.isEmpty && candidate.note.localizedCaseInsensitiveContains(trimmedTitle) {
                score += 2
            }
            if !trimmedNote.isEmpty && candidate.note.localizedCaseInsensitiveContains(trimmedNote) {
                score += 3
            }
            if let expenseCategoryID = advanceCase.expenseCategory?.id,
               candidate.category?.id == expenseCategoryID {
                score += 2
            }

            let dateDiff = abs(candidate.date.timeIntervalSince(advanceCase.date))
            if dateDiff <= 5 * 60 {
                score += 2
            } else if dateDiff <= 60 * 60 {
                score += 1
            }

            if score > bestScore || (score == bestScore && dateDiff < bestDateDiff) {
                bestScore = score
                bestDateDiff = dateDiff
                bestCandidate = candidate
            }
        }

        return bestCandidate
    }

    private static func decimalEquals(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        abs(lhs - rhs) <= roundingTolerance
    }

    private static func inferSettlementDirection(
        for participant: AdvanceParticipant,
        modelContext: ModelContext
    ) -> AdvanceSemantics.SettlementDirection {
        guard let groupID = participant.initialTransferGroupID else {
            return .iAdvancedOthers
        }
        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        let groupedTransfers = (try? modelContext.fetch(descriptor)) ?? []
        guard let outgoing = groupedTransfers.first(where: {
            $0.transferSide == .outgoing || $0.amount < 0
        }) else {
            return .iAdvancedOthers
        }
        return AdvanceSemantics.settlementDirection(
            debtAccountID: participant.debtAccount?.id,
            outgoingAccountID: outgoing.account?.id,
            outgoingNote: outgoing.note
        )
    }
}
