import XCTest
import SwiftData
@testable import AI_記帳

@MainActor
final class BackupCompatibilityTests: XCTestCase {
    func testLegacyAdvanceFixture_roundTripsWithoutHealthIssues() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fixtureURL = fixtureURL(named: "legacy_bidirectional_advances.json")
        try await BackupManager.shared.restoreFromJSON(url: fixtureURL, modelContext: modelContext)

        let initialReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertEqual(0, initialReport.errorCount)
        XCTAssertEqual(0, initialReport.warningCount)

        let exported = BackupManager.shared.createBackupData(modelContext: modelContext)
        XCTAssertEqual(5, exported.accounts.count)
        XCTAssertEqual(2, exported.categories.count)
        XCTAssertEqual(16, exported.transactions.count)
        XCTAssertEqual(2, exported.advanceCases?.count)
        XCTAssertEqual(3, exported.advanceParticipants?.count)
        XCTAssertEqual(4, exported.advanceRepayments?.count)
        XCTAssertEqual("Both", exported.categories.first(where: { $0.name == "Salary" })?.kind)

        let secondContainer = try makeInMemoryContainer()
        let secondContext = ModelContext(secondContainer)
        let exportedURL = try writeBackup(exported, named: "legacy-advance-roundtrip.json")
        try await BackupManager.shared.restoreFromJSON(url: exportedURL, modelContext: secondContext)

        let secondReport = DataHealthCheckService.run(modelContext: secondContext)
        XCTAssertEqual(0, secondReport.errorCount)
        XCTAssertEqual(0, secondReport.warningCount)

        let cases = try secondContext.fetch(FetchDescriptor<AdvanceCase>())
        XCTAssertEqual(2, cases.count)
    }

    func testLegacyDebtIncomeFixture_canRepairAndReimportCleanly() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fixtureURL = fixtureURL(named: "legacy_debt_income_repair.json")
        try await BackupManager.shared.restoreFromJSON(url: fixtureURL, modelContext: modelContext)

        let initialReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertTrue(initialReport.issues.contains(where: { $0.title == "收入記到了借貸帳戶" }))
        XCTAssertTrue(initialReport.issues.contains(where: { $0.title == "收入捷徑綁到了借貸帳戶" }))

        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let shortcuts = try modelContext.fetch(FetchDescriptor<Shortcut>())
        let convertedCount = try LegacyDebtIncomeRepairService.convertLegacyDebtIncomeTransactions(
            LegacyDebtIncomeRepairService.legacyDebtIncomeTransactions(from: transactions),
            modelContext: modelContext
        )
        let detachedCount = try LegacyDebtIncomeRepairService.detachLegacyDebtIncomeShortcuts(
            LegacyDebtIncomeRepairService.legacyDebtIncomeShortcuts(from: shortcuts),
            modelContext: modelContext
        )

        XCTAssertEqual(1, convertedCount)
        XCTAssertEqual(1, detachedCount)

        let repairedReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertFalse(repairedReport.issues.contains(where: { $0.title == "收入記到了借貸帳戶" }))
        XCTAssertFalse(repairedReport.issues.contains(where: { $0.title == "收入捷徑綁到了借貸帳戶" }))

        let exported = BackupManager.shared.createBackupData(modelContext: modelContext)
        XCTAssertEqual("Both", exported.categories.first(where: { $0.name == "Salary" })?.kind)
        XCTAssertEqual(1, exported.budgetHistory?.count)
        XCTAssertNil(exported.shortcuts.first?.accountID)
        XCTAssertEqual("Transfer", exported.transactions.first(where: { $0.id == UUID(uuidString: "34343434-3434-3434-3434-343434343431") })?.type)
        XCTAssertTrue((exported.transactions.first(where: { $0.id == UUID(uuidString: "34343434-3434-3434-3434-343434343431") })?.note ?? "").contains("[免除債務]"))

        let secondContainer = try makeInMemoryContainer()
        let secondContext = ModelContext(secondContainer)
        let exportedURL = try writeBackup(exported, named: "legacy-debt-income-roundtrip.json")
        try await BackupManager.shared.restoreFromJSON(url: exportedURL, modelContext: secondContext)

        let secondReport = DataHealthCheckService.run(modelContext: secondContext)
        XCTAssertFalse(secondReport.issues.contains(where: { $0.title == "收入記到了借貸帳戶" }))
        XCTAssertFalse(secondReport.issues.contains(where: { $0.title == "收入捷徑綁到了借貸帳戶" }))
        XCTAssertEqual(0, secondReport.errorCount)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Account.self,
            FinancialTransaction.self,
            Category.self,
            Tag.self,
            Shortcut.self,
            RecurringRule.self,
            RecurringOccurrence.self,
            CategoryMonthlyBudget.self,
            BudgetMonthlyHistory.self,
            BudgetSettings.self,
            AdvanceCase.self,
            AdvanceParticipant.self,
            AdvanceRepayment.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func fixtureURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func writeBackup(_ backup: FullBackupData, named name: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: tempURL, options: .atomic)
        return tempURL
    }
}

@MainActor
final class TransferPresentationServiceTests: XCTestCase {
    func testCounterpartMap_usesLinkedTransferPair() {
        let outgoingID = UUID()
        let incomingID = UUID()

        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: outgoingID, amount: -100, currencyCode: "USD", linkedTransactionID: incomingID, transferSide: .outgoing),
            transferInput(id: incomingID, amount: 780, currencyCode: "HKD", linkedTransactionID: outgoingID, transferSide: .incoming),
        ])

        XCTAssertEqual(result[outgoingID]?.amount, 780)
        XCTAssertEqual(result[outgoingID]?.currencyCode, "HKD")
        XCTAssertEqual(result[incomingID]?.amount, -100)
        XCTAssertEqual(result[incomingID]?.currencyCode, "USD")
    }

    func testCounterpartMap_handlesTransferGroupSplitMerge() {
        let groupID = UUID()
        let outgoingID = UUID()
        let firstIncomingID = UUID()
        let secondIncomingID = UUID()

        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: outgoingID, amount: -100, currencyCode: "HKD", transferGroupID: groupID, transferSide: .outgoing),
            transferInput(id: firstIncomingID, amount: 40, currencyCode: "HKD", transferGroupID: groupID, transferSide: .incoming),
            transferInput(id: secondIncomingID, amount: 60, currencyCode: "HKD", transferGroupID: groupID, transferSide: .incoming),
        ])

        XCTAssertNil(result[outgoingID])
        XCTAssertEqual(result[firstIncomingID]?.amount, -100)
        XCTAssertEqual(result[firstIncomingID]?.currencyCode, "HKD")
        XCTAssertEqual(result[secondIncomingID]?.amount, -100)
        XCTAssertEqual(result[secondIncomingID]?.currencyCode, "HKD")
    }

    func testCounterpartMap_ignoresMissingLinkedTransfer() {
        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: UUID(), amount: -100, currencyCode: "HKD", linkedTransactionID: UUID(), transferSide: .outgoing),
        ])

        XCTAssertTrue(result.isEmpty)
    }

    func testCounterpartMap_supportsSameAccountCrossCurrencyTransferShape() {
        let outgoingID = UUID()
        let incomingID = UUID()

        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: outgoingID, amount: -100, currencyCode: "HKD", linkedTransactionID: incomingID, transferSide: .outgoing),
            transferInput(id: incomingID, amount: 92, currencyCode: "CNY", linkedTransactionID: outgoingID, transferSide: .incoming),
        ])

        XCTAssertEqual(result[outgoingID]?.amount, 92)
        XCTAssertEqual(result[outgoingID]?.currencyCode, "CNY")
        XCTAssertEqual(result[incomingID]?.amount, -100)
        XCTAssertEqual(result[incomingID]?.currencyCode, "HKD")
    }

    private func transferInput(
        id: UUID,
        amount: Decimal,
        currencyCode: String,
        linkedTransactionID: UUID? = nil,
        transferGroupID: UUID? = nil,
        transferSide: TransferSide? = nil
    ) -> TransferCounterpartInput {
        TransferCounterpartInput(
            id: id,
            type: .transfer,
            amount: amount,
            currencyCode: currencyCode,
            linkedTransactionID: linkedTransactionID,
            transferGroupID: transferGroupID,
            transferSide: transferSide
        )
    }
}
