import XCTest
@testable import AI_記帳

final class AdvanceSemanticsTests: XCTestCase {
    func testTotalsUseExplicitScalarInputs() {
        XCTAssertEqual(
            Decimal(175),
            AdvanceSemantics.totalAdvanced(
                myShareAmount: 25,
                participantOwedAmounts: [100, 50]
            )
        )
        XCTAssertEqual(
            Decimal(90),
            AdvanceSemantics.outstanding(participantRemainingAmounts: [60, 30])
        )
    }

    func testRepaymentMarkerParsingDistinguishesValidAndInvalidSpecialRecords() {
        let offsetID = UUID()
        let settlementID = UUID()

        XCTAssertEqual(
            .mutualDebtOffset(offsetID),
            AdvanceSemantics.repaymentRecordKind(
                note: "\(AdvanceSemantics.mutualDebtOffsetMarker(id: offsetID)) offset"
            )
        )
        XCTAssertEqual(
            .manualDebtSettlement(settlementID),
            AdvanceSemantics.repaymentRecordKind(
                note: "\(AdvanceSemantics.manualDebtSettlementMarker(id: settlementID)) settlement"
            )
        )
        XCTAssertEqual(
            .invalidSpecial,
            AdvanceSemantics.repaymentRecordKind(note: "[債務抵銷:not-a-uuid]")
        )
        XCTAssertEqual(.ordinary, AdvanceSemantics.repaymentRecordKind(note: "repayment"))
    }

    func testLegacyDirectionEvidencePrefersDebtAccountAndBorrowedMarker() {
        let debtAccountID = UUID()

        XCTAssertEqual(
            .othersAdvancedMe,
            AdvanceSemantics.settlementDirection(
                debtAccountID: debtAccountID,
                outgoingAccountID: debtAccountID,
                outgoingNote: ""
            )
        )
        XCTAssertEqual(
            .othersAdvancedMe,
            AdvanceSemantics.settlementDirection(
                debtAccountID: debtAccountID,
                outgoingAccountID: UUID(),
                outgoingNote: "Dinner (他人代墊我：Friend)"
            )
        )
        XCTAssertEqual(
            .iAdvancedOthers,
            AdvanceSemantics.settlementDirection(
                debtAccountID: debtAccountID,
                outgoingAccountID: UUID(),
                outgoingNote: "Dinner (代墊給 Friend)"
            )
        )
    }
}
