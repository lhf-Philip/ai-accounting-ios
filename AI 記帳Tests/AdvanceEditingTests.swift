import XCTest
import SwiftData
@testable import AI_記帳

@MainActor
final class AdvanceEditingTests: XCTestCase {
    func testInitialEntrySupportsActualPaymentCurrencySeparateFromDebtCurrency() throws {
        let context = try makeContext()
        let bank = Account(name: "HSBC HKD", currency: "HKD", type: .bank, baseBalance: 0)
        let friend = Account(name: "TKL", currency: "JPY", type: .debt, baseBalance: 0)
        let replacementDebt = Account(name: "TKL Travel", currency: "JPY", type: .debt, baseBalance: 0)
        [bank, friend, replacementDebt].forEach(context.insert)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "LUUP",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "",
            payerAccount: bank,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 710)],
            modelContext: context
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)

        try AdvanceService.updateInitialEntry(
            advanceCase: advanceCase,
            participant: participant,
            draft: .init(
                participantName: "TKL Travel",
                debtAccount: replacementDebt,
                payerAccount: bank,
                owedAmount: 710,
                paymentAmount: Decimal(string: "34.86"),
                paymentCurrencyCode: "HKD",
                date: Date(timeIntervalSince1970: 20),
                note: "LUUP",
                category: nil,
                tags: []
            ),
            modelContext: context
        )

        let groupID = try XCTUnwrap(participant.initialTransferGroupID)
        let group = try fetchGroup(groupID, context: context)
        let asset = try XCTUnwrap(group.first { $0.advanceEntryRole == .initialAsset })
        let debt = try XCTUnwrap(group.first { $0.advanceEntryRole == .initialDebt })
        XCTAssertEqual(Decimal(string: "-34.86"), asset.amount)
        XCTAssertEqual("HKD", asset.currencyCode)
        XCTAssertEqual(Decimal(710), debt.amount)
        XCTAssertEqual("JPY", debt.currencyCode)
        XCTAssertEqual("TKL Travel", participant.name)
        XCTAssertEqual(replacementDebt.id, participant.debtAccount?.id)
        XCTAssertEqual(replacementDebt.id, debt.account?.id)
        XCTAssertEqual(advanceCase.id, asset.advanceCaseID)
        XCTAssertEqual(participant.id, debt.advanceParticipantID)
    }

    func testCrossCurrencyRepaymentEditPreservesExplicitNormalizedAmountAndIncomingMetadata() throws {
        let context = try makeContext()
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let bank = Account(name: "Bank", currency: "HKD", type: .bank, baseBalance: 0)
        let friend = Account(name: "Friend", currency: "JPY", type: .debt, baseBalance: 0)
        let category = Category(name: "Repayment received", icon: "arrow.down", colorHex: "#123456", kind: .income)
        let tag = Tag(name: "Edited")
        [wallet, bank, friend].forEach(context.insert)
        context.insert(category)
        context.insert(tag)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Japan trip",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "",
            payerAccount: wallet,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 2_000)],
            modelContext: context
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)
        let repayment = try AdvanceService.recordRepayment(
            advanceCase: advanceCase,
            participant: participant,
            amount: 50,
            currencyCode: "HKD",
            date: Date(timeIntervalSince1970: 20),
            note: "First",
            receiveAccount: wallet,
            category: nil,
            tags: [],
            currencyService: .shared,
            normalizedAmountOverride: 1_000,
            direction: .iAdvancedOthers,
            modelContext: context
        )

        try AdvanceService.updateRepayment(
            advanceCase: advanceCase,
            repayment: repayment,
            draft: .init(
                receiveAccount: bank,
                amount: 60,
                currencyCode: "HKD",
                normalizedAmount: 900,
                date: Date(timeIntervalSince1970: 30),
                note: "Edited",
                category: category,
                tags: [tag]
            ),
            modelContext: context
        )

        XCTAssertEqual(Decimal(60), repayment.amount)
        XCTAssertEqual(Decimal(900), repayment.normalizedAmount)
        XCTAssertEqual(Decimal(900), participant.repaidAmount)
        XCTAssertEqual(bank.id, repayment.receivedAccount?.id)

        let groupID = try XCTUnwrap(repayment.linkedTransferGroupID)
        let transactions = try fetchGroup(groupID, context: context)
        let incoming = try XCTUnwrap(transactions.first { $0.transferSide == .incoming })
        let outgoing = try XCTUnwrap(transactions.first { $0.transferSide == .outgoing })
        XCTAssertEqual(bank.id, incoming.account?.id)
        XCTAssertEqual(category.id, incoming.category?.id)
        XCTAssertEqual([tag.id], incoming.tags.map(\.id))
        XCTAssertNil(outgoing.category)
        XCTAssertTrue(outgoing.tags.isEmpty)
    }

    func testOthersAdvancedMeEditTagsOutgoingOwnLegAndRollbackRestoresParticipant() throws {
        let context = try makeContext()
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let friend = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        let category = Category(name: "Repayment paid", icon: "arrow.up", colorHex: "#654321", kind: .expense)
        let tag = Tag(name: "Paid")
        [wallet, friend].forEach(context.insert)
        context.insert(category)
        context.insert(tag)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Dinner",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "",
            payerAccount: nil,
            category: category,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 100)],
            isBorrowedByMe: true,
            modelContext: context
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)
        let repayment = try AdvanceService.recordRepayment(
            advanceCase: advanceCase,
            participant: participant,
            amount: 40,
            currencyCode: "HKD",
            date: Date(timeIntervalSince1970: 20),
            note: "",
            receiveAccount: wallet,
            category: nil,
            tags: [],
            currencyService: .shared,
            normalizedAmountOverride: 40,
            direction: .othersAdvancedMe,
            modelContext: context
        )

        try AdvanceService.updateRepayment(
            advanceCase: advanceCase,
            repayment: repayment,
            draft: .init(
                receiveAccount: wallet,
                amount: 35,
                currencyCode: "HKD",
                normalizedAmount: 35,
                date: Date(timeIntervalSince1970: 30),
                note: "Paid",
                category: category,
                tags: [tag]
            ),
            modelContext: context
        )

        let groupID = try XCTUnwrap(repayment.linkedTransferGroupID)
        let outgoing = try XCTUnwrap(
            fetchGroup(groupID, context: context).first { $0.transferSide == .outgoing }
        )
        XCTAssertEqual(wallet.id, outgoing.account?.id)
        XCTAssertEqual(category.id, outgoing.category?.id)
        XCTAssertEqual([tag.id], outgoing.tags.map(\.id))

        try AdvanceService.rollbackRepayment(
            advanceCase: advanceCase,
            repayment: repayment,
            modelContext: context
        )

        XCTAssertEqual(Decimal.zero, participant.repaidAmount)
        XCTAssertTrue(try fetchGroup(groupID, context: context).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AdvanceRepayment>()).isEmpty)
    }

    func testParticipantCorrectionUpdatesBorrowedInitialExpense() throws {
        let context = try makeContext()
        let friend = Account(name: "Friend", currency: "JPY", type: .debt, baseBalance: 0)
        let category = Category(name: "Transport", icon: "tram", colorHex: "#123456", kind: .expense)
        let tag = Tag(name: "Trip")
        context.insert(friend)
        context.insert(category)
        context.insert(tag)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Taxi",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "",
            payerAccount: nil,
            category: category,
            tags: [tag],
            participants: [.init(debtAccount: friend, owedAmount: 1_000)],
            isBorrowedByMe: true,
            modelContext: context
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)

        try AdvanceService.updateParticipantOwedAmount(
            advanceCase: advanceCase,
            participant: participant,
            newOwedAmount: 1_200,
            modelContext: context
        )

        XCTAssertEqual(Decimal(1_200), participant.owedAmount)
        let groupID = try XCTUnwrap(participant.initialTransferGroupID)
        let expense = try XCTUnwrap(fetchGroup(groupID, context: context).first)
        XCTAssertEqual(.expense, expense.type)
        XCTAssertEqual(Decimal(-1_200), expense.amount)
        XCTAssertEqual("JPY", expense.currencyCode)
        XCTAssertEqual(category.id, expense.category?.id)
        XCTAssertEqual([tag.id], expense.tags.map(\.id))

        let report = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: [
                    ReportTransactionSnapshot(
                        id: expense.id,
                        amount: expense.amount,
                        currencyCode: expense.currencyCode,
                        date: expense.date,
                        type: expense.type,
                        categoryID: expense.category?.id,
                        categoryName: expense.category?.name,
                        categoryColorHex: expense.category?.colorHex,
                        tagNames: expense.tags.map(\.name)
                    )
                ],
                flow: .expense,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: AdvanceEditingReportCurrencyConverter(mainCurrency: "JPY")
        )

        let slice = try XCTUnwrap(report.slices.first)
        XCTAssertEqual("Transport", slice.name)
        XCTAssertEqual(Decimal(1_200), slice.estimatedAmount)
        XCTAssertEqual(
            [ReportCurrencyTotal(currencyCode: "JPY", amount: 1_200)],
            slice.originalCurrencyTotals
        )
        XCTAssertEqual([expense.id], slice.transactionIDs)
    }

    func testInitialEntryEditUpdatesCaseMetadataAcrossEveryParticipant() throws {
        let context = try makeContext()
        let wallet = Account(name: "Wallet", currency: "JPY", type: .cash, baseBalance: 0)
        let bank = Account(name: "Bank", currency: "JPY", type: .bank, baseBalance: 0)
        let friendA = Account(name: "Friend A", currency: "JPY", type: .debt, baseBalance: 0)
        let friendB = Account(name: "Friend B", currency: "JPY", type: .debt, baseBalance: 0)
        [wallet, bank, friendA, friendB].forEach(context.insert)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Japan trip",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "Original",
            payerAccount: wallet,
            category: nil,
            tags: [],
            participants: [
                .init(debtAccount: friendA, owedAmount: 100),
                .init(debtAccount: friendB, owedAmount: 200),
            ],
            modelContext: context
        )
        let participantA = try XCTUnwrap(
            advanceCase.participants.first { $0.debtAccount?.id == friendA.id }
        )
        let participantB = try XCTUnwrap(
            advanceCase.participants.first { $0.debtAccount?.id == friendB.id }
        )
        let editedDate = Date(timeIntervalSince1970: 50)

        try AdvanceService.updateInitialEntry(
            advanceCase: advanceCase,
            participant: participantA,
            draft: .init(
                payerAccount: bank,
                owedAmount: 120,
                paymentAmount: 120,
                paymentCurrencyCode: "HKD",
                date: editedDate,
                note: "Edited",
                category: nil,
                tags: []
            ),
            modelContext: context
        )

        XCTAssertEqual(Decimal(120), participantA.owedAmount)
        XCTAssertEqual(Decimal(200), participantB.owedAmount)
        XCTAssertNil(advanceCase.payerAccount)
        XCTAssertEqual(editedDate, advanceCase.date)
        XCTAssertEqual("Edited", advanceCase.note)

        for participant in [participantA, participantB] {
            let groupID = try XCTUnwrap(participant.initialTransferGroupID)
            let transactions = try fetchGroup(groupID, context: context)
            let outgoing = try XCTUnwrap(
                transactions.first { $0.transferSide == .outgoing }
            )
            let incoming = try XCTUnwrap(
                transactions.first { $0.transferSide == .incoming }
            )
            let expectedPaymentAccount = participant.id == participantA.id ? bank : wallet
            XCTAssertEqual(expectedPaymentAccount.id, outgoing.account?.id)
            XCTAssertEqual(editedDate, outgoing.date)
            XCTAssertEqual(editedDate, incoming.date)
            XCTAssertTrue(incoming.note.contains(expectedPaymentAccount.name))
            XCTAssertEqual(participant.owedAmount, abs(outgoing.amount))
            XCTAssertEqual(participant.owedAmount, incoming.amount)
        }
    }

    func testSelfExpenseEditPreservesActualCurrencyAndNormalisedCaseShare() throws {
        let context = try makeContext()
        let wallet = Account(name: "Wallet", currency: "HKD", type: .creditCard, baseBalance: 0)
        let friend = Account(name: "Friend", currency: "JPY", type: .debt, baseBalance: 0)
        let category = Category(name: "Transport", icon: "tram", colorHex: "#123456", kind: .expense)
        let tag = Tag(name: "LUUP")
        [wallet, friend].forEach(context.insert)
        context.insert(category)
        context.insert(tag)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Japan trip",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "JPY",
            myShareAmount: 1_000,
            note: "",
            payerAccount: wallet,
            category: category,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 2_000)],
            modelContext: context
        )
        let transactionID = try XCTUnwrap(advanceCase.selfExpenseTransactionID)
        let transaction = try XCTUnwrap(
            try context.fetch(
                FetchDescriptor<FinancialTransaction>(
                    predicate: #Predicate { $0.id == transactionID }
                )
            ).first
        )

        try AdvanceService.updateSelfExpense(
            advanceCase: advanceCase,
            transaction: transaction,
            draft: .init(
                account: wallet,
                amount: Decimal(string: "35.59")!,
                currencyCode: "CHF",
                normalizedAmount: 725,
                date: Date(timeIntervalSince1970: 20),
                note: "LUUP",
                category: category,
                tags: [tag]
            ),
            modelContext: context
        )

        XCTAssertEqual(Decimal(string: "-35.59")!, transaction.amount)
        XCTAssertEqual("CHF", transaction.currencyCode)
        XCTAssertEqual(Decimal(725), advanceCase.myShareAmount)
        XCTAssertEqual(category.id, transaction.category?.id)
        XCTAssertEqual([tag.id], transaction.tags.map(\.id))

        let report = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: [
                    ReportTransactionSnapshot(
                        id: transaction.id,
                        amount: transaction.amount,
                        currencyCode: transaction.currencyCode,
                        date: transaction.date,
                        type: transaction.type,
                        categoryID: transaction.category?.id,
                        categoryName: transaction.category?.name,
                        categoryColorHex: transaction.category?.colorHex,
                        tagNames: transaction.tags.map(\.name)
                    )
                ],
                flow: .expense,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: AdvanceEditingReportCurrencyConverter(mainCurrency: "CHF")
        )

        let slice = try XCTUnwrap(report.slices.first)
        XCTAssertEqual(Decimal(string: "35.59")!, slice.estimatedAmount)
        XCTAssertEqual(
            [ReportCurrencyTotal(currencyCode: "CHF", amount: Decimal(string: "35.59")!)],
            slice.originalCurrencyTotals
        )
    }

    func testRepaymentEditRejectsCategoryForWrongSettlementDirection() throws {
        let context = try makeContext()
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let friend = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        let expenseCategory = Category(
            name: "Wrong direction",
            icon: "xmark",
            colorHex: "#123456",
            kind: .expense
        )
        [wallet, friend].forEach(context.insert)
        context.insert(expenseCategory)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Dinner",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "",
            payerAccount: wallet,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 100)],
            modelContext: context
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)
        let repayment = try AdvanceService.recordRepayment(
            advanceCase: advanceCase,
            participant: participant,
            amount: 40,
            currencyCode: "HKD",
            date: Date(timeIntervalSince1970: 20),
            note: "",
            receiveAccount: wallet,
            category: nil,
            tags: [],
            currencyService: .shared,
            normalizedAmountOverride: 40,
            modelContext: context
        )

        XCTAssertThrowsError(
            try AdvanceService.updateRepayment(
                advanceCase: advanceCase,
                repayment: repayment,
                draft: .init(
                    receiveAccount: wallet,
                    amount: 35,
                    currencyCode: "HKD",
                    normalizedAmount: 35,
                    date: Date(timeIntervalSince1970: 30),
                    note: "",
                    category: expenseCategory,
                    tags: []
                ),
                modelContext: context
            )
        ) { error in
            XCTAssertEqual(
                AdvanceServiceError.invalidSettlementCategory.localizedDescription,
                error.localizedDescription
            )
        }
        XCTAssertEqual(Decimal(40), repayment.amount)
        XCTAssertEqual(Decimal(40), participant.repaidAmount)
    }

    func testExplicitLinkBackfillUsesExistingCaseAndGroupIdentifiers() throws {
        let context = try makeContext()
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let friend = Account(name: "Friend", currency: "JPY", type: .debt, baseBalance: 0)
        [wallet, friend].forEach(context.insert)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "LUUP",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "",
            payerAccount: wallet,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 710)],
            modelContext: context
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)
        let entries = try fetchGroup(
            try XCTUnwrap(participant.initialTransferGroupID),
            context: context
        )
        for entry in entries {
            entry.advanceCaseID = nil
            entry.advanceParticipantID = nil
            entry.advanceEntryRole = nil
        }
        advanceCase.direction = nil
        try context.save()

        let result = try AdvanceService.backfillExplicitLinks(modelContext: context)

        XCTAssertEqual(2, result.linkedTransactionCount)
        XCTAssertEqual(.iAdvancedOthers, advanceCase.direction)
        XCTAssertTrue(entries.allSatisfy { $0.advanceCaseID == advanceCase.id })
        XCTAssertTrue(entries.allSatisfy { $0.advanceParticipantID == participant.id })
        XCTAssertEqual(
            Set([AdvanceEntryRole.initialAsset, AdvanceEntryRole.initialDebt]),
            Set(entries.compactMap(\.advanceEntryRole))
        )
    }

    func testCaseEditingRejectsDirectionChangeBeforeMutatingCase() throws {
        let context = try makeContext()
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let friend = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        [wallet, friend].forEach(context.insert)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Dinner",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "",
            payerAccount: wallet,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 100)],
            modelContext: context
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)
        let draft = AdvanceCaseEditDraft(
            advanceCase: advanceCase,
            title: "Changed",
            date: advanceCase.date,
            direction: .othersAdvancedMe,
            currencyCode: advanceCase.currencyCode,
            note: advanceCase.note,
            category: nil,
            tags: [],
            share: nil,
            participants: [
                AdvanceParticipantDraft(
                    participant: participant,
                    name: participant.name,
                    debtAccount: friend,
                    owedAmount: participant.owedAmount,
                    paymentLegs: []
                )
            ],
            repayments: []
        )

        XCTAssertThrowsError(
            try AdvanceCaseEditingService.apply(draft, modelContext: context)
        ) { error in
            XCTAssertEqual(
                AdvanceCaseEditingError.unsupportedDirectionChange.localizedDescription,
                error.localizedDescription
            )
        }
        XCTAssertEqual("Dinner", advanceCase.title)
        XCTAssertEqual(.iAdvancedOthers, advanceCase.direction)
    }

    private func makeContext() throws -> ModelContext {
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
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fetchGroup(_ groupID: UUID, context: ModelContext) throws -> [FinancialTransaction] {
        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        return try context.fetch(descriptor)
    }
}

private struct AdvanceEditingReportCurrencyConverter: ReportCurrencyConverting {
    let mainCurrency: String

    func estimateInMainCurrency(amount: Decimal, from currencyCode: String) -> ReportConversion? {
        guard currencyCode.caseInsensitiveCompare(mainCurrency) == .orderedSame else {
            return nil
        }
        return ReportConversion(amount: amount, status: .exact)
    }
}
