#if DEBUG
import Foundation
import SwiftData

@MainActor
enum UITestSeedService {
    static func seedLedgerPerformanceData(in modelContext: ModelContext) {
        do {
            let existing = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
            guard !existing.contains(where: { $0.note.contains("UITest") }) else { return }
        } catch {
            return
        }

        let cash = Account(name: "UITest Cash", currency: "HKD", type: .cash, baseBalance: 1_000, sortOrder: 1)
        let bank = Account(name: "UITest Bank HKD", currency: "HKD", type: .bank, baseBalance: 8_000, sortOrder: 2)
        let usdPocket = Account(name: "UITest Bank USD", currency: "USD", type: .bank, baseBalance: 500, sortOrder: 3)
        let friendDebt = Account(name: "UITest Friend Debt", currency: "HKD", type: .debt, baseBalance: 0, sortOrder: 4)

        let food = Category(name: "UITest Food", icon: "fork.knife", colorHex: "FF9500", kind: .expense)
        let repaymentCategory = Category(name: "UITest Repayment", icon: "arrow.down.circle", colorHex: "30B0C7", kind: .income)
        let tag = Tag(name: "UITest")

        modelContext.insert(cash)
        modelContext.insert(bank)
        modelContext.insert(usdPocket)
        modelContext.insert(friendDebt)
        modelContext.insert(food)
        modelContext.insert(repaymentCategory)
        modelContext.insert(tag)

        let now = Date()
        let expense = FinancialTransaction(
            amount: -42,
            currencyCode: "HKD",
            date: now.addingTimeInterval(-60),
            note: "UITest 普通支出",
            type: .expense,
            account: cash,
            category: food,
            tags: [tag]
        )

        let transferGroupID = UUID()
        let transferOutID = UUID()
        let transferInID = UUID()
        let transferOut = FinancialTransaction(
            id: transferOutID,
            amount: -100,
            currencyCode: "HKD",
            date: now.addingTimeInterval(-120),
            note: "UITest 轉帳",
            type: .transfer,
            linkedTransactionID: transferInID,
            transferGroupID: transferGroupID,
            transferSide: .outgoing,
            account: bank
        )
        let transferIn = FinancialTransaction(
            id: transferInID,
            amount: 12.8,
            currencyCode: "USD",
            date: now.addingTimeInterval(-120),
            note: "UITest 轉帳",
            type: .transfer,
            linkedTransactionID: transferOutID,
            transferGroupID: transferGroupID,
            transferSide: .incoming,
            account: usdPocket
        )

        modelContext.insert(expense)
        modelContext.insert(transferOut)
        modelContext.insert(transferIn)

        do {
            let advanceCase = try AdvanceService.createAdvanceCase(
                title: "UITest 代墊晚餐",
                date: now.addingTimeInterval(-180),
                currencyCode: "HKD",
                myShareAmount: 50,
                note: "UITest 代墊案件",
                payerAccount: cash,
                category: food,
                tags: [tag],
                participants: [
                    AdvanceService.ParticipantInput(
                        debtAccount: friendDebt,
                        owedAmount: 80
                    )
                ],
                modelContext: modelContext
            )
            guard let participant = advanceCase.participants.first else {
                throw AdvanceServiceError.noParticipants
            }
            _ = try AdvanceService.recordRepayment(
                advanceCase: advanceCase,
                participant: participant,
                amount: 20,
                currencyCode: "HKD",
                date: now.addingTimeInterval(-120),
                note: "UITest 代墊還款",
                receiveAccount: bank,
                category: repaymentCategory,
                tags: [tag],
                currencyService: CurrencyService.shared,
                normalizedAmountOverride: 20,
                modelContext: modelContext
            )
            try modelContext.save()
        } catch {
            print("⚠️ UI test seed failed: \(error)")
        }
    }
}
#endif
