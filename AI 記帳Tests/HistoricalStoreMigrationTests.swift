import XCTest
import SwiftData
import CryptoKit
@testable import AI_記帳

@MainActor
final class HistoricalStoreMigrationTests: XCTestCase {
    func testTransferEra() throws { try verify("transfer", level: 0) }
    func testBudgetEra() throws { try verify("budget", level: 1) }
    func testAdvanceEra() throws { try verify("advance", level: 2) }
    func testAdvanceLinksEra() throws { try verify("advance_links", level: 3) }
    func testBudgetHistoryEra() throws { try verify("history", level: 4) }
    func testBudgetSettingsEra() throws { try verify("settings", level: 5) }
    func testRecurringEra() throws { try verify("recurring", level: 6) }
    func testRequiredAdvanceTagsEra() throws { try verify("pre_v2", level: 7) }

    private let storeName = "AI_Accounting_v3.store"
    private let date = Date(timeIntervalSince1970: 1700000000)

    private func verify(_ era: String, level: Int) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SwiftData/Historical")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixture.appendingPathComponent("\(era).manifest.json")))
        XCTAssertFalse(manifest.files.isEmpty)
        for (name, digest) in manifest.files {
            let bytes = try Data(contentsOf: fixture.appendingPathComponent(era + name.replacingOccurrences(of: "AI_Accounting_v3", with: "")))
            XCTAssertEqual(hash(bytes), digest, "Historical fixture changed: \(era)/\(name)")
            try bytes.write(to: directory.appendingPathComponent(name))
        }
        // Producer already exited before these committed fixtures were captured. Reopen with a new context/container.
        for _ in 0..<2 {
            try autoreleasepool {
                let service = StoreStartupService(documents: { directory }, prepare: { _ in })
                let container: ModelContainer
                switch service.load() {
                case .success(let opened): container = opened
                case .failure(let failure): throw failure
                }
                let context = ModelContext(container)
                defer { withExtendedLifetime(context) {} }
                let categories = try context.fetch(FetchDescriptor<AI_記帳.Category>())
                XCTAssertEqual(categories.count, 3)
                for (index, kind) in [(2, CategoryKind.expense), (14, .income), (15, .both)] {
                    let category = try XCTUnwrap(categories.first { $0.id == id(index) })
                    XCTAssertEqual(category.storedKind, kind)
                    XCTAssertEqual(category.kind, kind)
                }
                let accounts = try context.fetch(FetchDescriptor<Account>())
                XCTAssertEqual(accounts.count, 2)
                XCTAssertEqual(accounts.first { $0.id == id(1) }?.currentBalance, decimal("1114.41"))
                XCTAssertEqual(accounts.first { $0.id == id(6) }?.currentBalance, decimal("62.80"))
                let transactions = try context.fetch(FetchDescriptor<FinancialTransaction>())
                XCTAssertEqual(transactions.count, 4)
                let expense = try XCTUnwrap(transactions.first { $0.id == id(4) })
                XCTAssertEqual(expense.amount, decimal("-35.59"))
                XCTAssertEqual(expense.date, date)
                XCTAssertEqual(expense.account?.id, id(1))
                XCTAssertEqual(expense.category?.id, id(2))
                XCTAssertEqual(expense.tags.map(\.id), [id(3)])
                for (index, linkedID, side) in [(8, 9, TransferSide.outgoing), (9, 8, .incoming)] {
                    let transfer = try XCTUnwrap(transactions.first { $0.id == id(index) })
                    XCTAssertEqual(transfer.linkedTransactionID, id(linkedID))
                    XCTAssertEqual(transfer.transferGroupID, id(30))
                    XCTAssertEqual(transfer.transferSide, side)
                }
                let shortcut = try one(Shortcut.self, context, id: 5)
                XCTAssertEqual(shortcut.account?.id, id(1))
                XCTAssertEqual(shortcut.category?.id, id(2))
                XCTAssertEqual(shortcut.tags.map(\.id), [id(3)])
                if level >= 1 {
                    let budget = try one(CategoryMonthlyBudget.self, context, id: 20)
                    XCTAssertEqual(budget.category?.id, id(2))
                    XCTAssertEqual(budget.monthKey, "2023-11")
                    XCTAssertEqual(budget.amount, decimal("500.50"))
                }
                if level >= 2 {
                    let advance = try one(AdvanceCase.self, context, id: 21)
                    XCTAssertEqual(advance.myShareAmount, decimal("35.59"))
                    XCTAssertEqual(advance.payerAccount?.id, id(1))
                    XCTAssertEqual(advance.expenseCategory?.id, id(2))
                    XCTAssertEqual(advance.tagIDs, level >= 7 ? [id(3)] : [])
                    let participant = try one(AdvanceParticipant.self, context, id: 22)
                    XCTAssertEqual(participant.advanceCase?.id, id(21))
                    XCTAssertEqual(participant.owedAmount, decimal("20.25"))
                    XCTAssertEqual(participant.repaidAmount, decimal("10.10"))
                    let repayment = try one(AdvanceRepayment.self, context, id: 23)
                    XCTAssertEqual(repayment.advanceCase?.id, id(21))
                    XCTAssertEqual(repayment.participant?.id, id(22))
                    XCTAssertEqual(repayment.receivedAccount?.id, id(1))
                    XCTAssertEqual(repayment.amount, decimal("10.10"))
                    XCTAssertEqual(repayment.normalizedAmount, decimal("10.10"))
                    XCTAssertEqual(repayment.linkedTransferGroupID, id(31))
                    if level >= 3 {
                        XCTAssertEqual(advance.selfExpenseTransactionID, id(4))
                        XCTAssertEqual(participant.initialTransferGroupID, id(30))
                    }
                    if level >= 7 {
                        XCTAssertEqual(advance.direction, .iAdvancedOthers)
                        XCTAssertEqual(expense.advanceCaseID, id(21))
                        XCTAssertEqual(expense.advanceParticipantID, id(22))
                        XCTAssertEqual(expense.advanceRepaymentID, id(23))
                        XCTAssertEqual(expense.advanceEntryRole, .selfExpense)
                    }
                }
                if level >= 4 {
                    let history = try one(BudgetMonthlyHistory.self, context, id: 24)
                    XCTAssertEqual(history.categoryID, id(2))
                    XCTAssertEqual(history.historyKey, "2023-11-synthetic")
                    XCTAssertEqual(history.budgetAmount, decimal("500.50"))
                    XCTAssertEqual(history.spentAmount, decimal("35.59"))
                    XCTAssertEqual(history.remainingAmount, decimal("464.91"))
                    XCTAssertEqual(history.usageRatio, decimal("0.0711088911"))
                }
                if level >= 5 {
                    let settings = try context.fetch(FetchDescriptor<BudgetSettings>())
                    XCTAssertEqual(settings.count, 1)
                    XCTAssertEqual(settings.first?.id, "global")
                    XCTAssertEqual(settings.first?.carryOverMode, .netBalance)
                    XCTAssertEqual(settings.first?.alertThresholdPercent, decimal("85.50"))
                }
                if level >= 6 {
                    let rule = try one(RecurringRule.self, context, id: 25)
                    XCTAssertEqual(rule.amount, decimal("8.25"))
                    XCTAssertEqual(rule.frequency, .weekly)
                    XCTAssertEqual(rule.intervalCount, 2)
                    XCTAssertEqual(rule.nextDueDate, date)
                    XCTAssertEqual(rule.account?.id, id(1))
                    XCTAssertEqual(rule.category?.id, id(2))
                    XCTAssertEqual(rule.tags.map(\.id), [id(3)])
                    let occurrence = try one(RecurringOccurrence.self, context, id: 26)
                    XCTAssertEqual(occurrence.rule?.id, id(25))
                    XCTAssertEqual(occurrence.status, .confirmed)
                    XCTAssertEqual(occurrence.createdTransactionID, id(4))
                }
            }
        }
        let snapshot = try XCTUnwrap(StoreMigrationSafetyService.latestCompleteBackup(storeURL: directory.appendingPathComponent(storeName)))
        for (name, digest) in manifest.files {
            XCTAssertEqual(hash(try Data(contentsOf: snapshot.appendingPathComponent(name))), digest)
            XCTAssertEqual(hash(try Data(contentsOf: fixture.appendingPathComponent(era + name.replacingOccurrences(of: "AI_Accounting_v3", with: "")))), digest)
        }
    }

    private struct Manifest: Decodable { let files: [String: String] }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func decimal(_ value: String) -> Decimal { Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))! }
    private func id(_ index: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))! }
    private func one<T: PersistentModel>(_ type: T.Type, _ context: ModelContext, id index: Int) throws -> T where T.ID == UUID {
        let rows = try context.fetch(FetchDescriptor<T>())
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.id, id(index))
        return row
    }
}
