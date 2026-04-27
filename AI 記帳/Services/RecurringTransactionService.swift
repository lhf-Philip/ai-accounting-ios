import Foundation
import SwiftData

enum RecurringTransactionError: LocalizedError {
    case missingRule
    case missingAccount
    case invalidType

    var errorDescription: String? {
        switch self {
        case .missingRule:
            return "找不到對應的定期規則。"
        case .missingAccount:
            return "此規則缺少帳戶，請先編輯規則。"
        case .invalidType:
            return "定期記帳 v1 只支援收入與支出。"
        }
    }
}

enum RecurringTransactionService {
    static func syncDueOccurrences(
        rules: [RecurringRule],
        occurrences: [RecurringOccurrence],
        now: Date = Date(),
        modelContext: ModelContext
    ) throws {
        for rule in rules where !rule.isPaused {
            guard rule.type == .income || rule.type == .expense else { continue }

            var dueDate = rule.nextDueDate
            var generatedCount = 0
            let existingDueDates = occurrences
                .filter { $0.rule?.id == rule.id }
                .map(\.dueDate)

            while dueDate <= now, generatedCount < 24 {
                let alreadyExists = existingDueDates.contains { Calendar.current.isDate($0, equalTo: dueDate, toGranularity: .minute) }
                if !alreadyExists {
                    let occurrence = RecurringOccurrence(dueDate: dueDate, rule: rule)
                    modelContext.insert(occurrence)
                }

                dueDate = nextDate(after: dueDate, frequency: rule.frequency, intervalCount: rule.intervalCount)
                generatedCount += 1
            }

            if dueDate != rule.nextDueDate {
                rule.nextDueDate = dueDate
                rule.updatedAt = now
            }
        }

        try modelContext.save()
    }

    @discardableResult
    static func confirm(
        occurrence: RecurringOccurrence,
        modelContext: ModelContext
    ) throws -> FinancialTransaction {
        guard let rule = occurrence.rule else { throw RecurringTransactionError.missingRule }
        guard rule.type == .income || rule.type == .expense else { throw RecurringTransactionError.invalidType }
        guard let account = rule.account else { throw RecurringTransactionError.missingAccount }

        if let createdID = occurrence.createdTransactionID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.id == createdID }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                occurrence.status = .confirmed
                try modelContext.save()
                return existing
            }
        }

        let signedAmount = rule.type == .expense ? -abs(rule.amount) : abs(rule.amount)
        let transaction = FinancialTransaction(
            amount: signedAmount,
            currencyCode: rule.currencyCode,
            date: occurrence.dueDate,
            note: rule.note.isEmpty ? rule.title : rule.note,
            type: rule.type,
            account: account,
            category: rule.category,
            tags: rule.tags
        )
        modelContext.insert(transaction)
        occurrence.createdTransactionID = transaction.id
        occurrence.status = .confirmed
        rule.updatedAt = Date()
        try modelContext.save()
        return transaction
    }

    static func skip(
        occurrence: RecurringOccurrence,
        modelContext: ModelContext
    ) throws {
        occurrence.status = .skipped
        occurrence.updatedAt = Date()
        try modelContext.save()
    }

    static func nextDate(after date: Date, frequency: RecurringFrequency, intervalCount: Int) -> Date {
        let value = max(1, intervalCount)
        let component: Calendar.Component
        switch frequency {
        case .daily:
            component = .day
        case .weekly:
            component = .weekOfYear
        case .monthly:
            component = .month
        }
        return Calendar.current.date(byAdding: component, value: value, to: date) ?? date
    }
}
