import Foundation

enum AdvanceSemantics {
    enum RepaymentRecordKind: Equatable {
        case ordinary
        case mutualDebtOffset(UUID)
        case manualDebtSettlement(UUID)
        case invalidSpecial
    }

    enum SettlementDirection {
        case iAdvancedOthers
        case othersAdvancedMe
    }

    static let mutualDebtOffsetMarkerPrefix = "[債務抵銷:"
    static let manualDebtSettlementMarkerPrefix = "[跨幣種平賬:"

    static func totalAdvanced(
        myShareAmount: Decimal,
        participantOwedAmounts: [Decimal]
    ) -> Decimal {
        myShareAmount + participantOwedAmounts.reduce(.zero, +)
    }

    static func outstanding(participantRemainingAmounts: [Decimal]) -> Decimal {
        participantRemainingAmounts.reduce(.zero, +)
    }

    static func settlementDirection(
        debtAccountID: UUID?,
        outgoingAccountID: UUID?,
        outgoingNote: String
    ) -> SettlementDirection {
        if let debtAccountID, outgoingAccountID == debtAccountID {
            return .othersAdvancedMe
        }

        let compactedNote = outgoingNote.replacingOccurrences(of: " ", with: "")
        if compactedNote.contains("(代墊給我") || compactedNote.contains("(他人代墊我") {
            return .othersAdvancedMe
        }
        return .iAdvancedOthers
    }

    static func isMutualDebtOffset(note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix(mutualDebtOffsetMarkerPrefix)
    }

    static func mutualDebtOffsetMarker(id: UUID) -> String {
        "\(mutualDebtOffsetMarkerPrefix)\(id.uuidString)]"
    }

    static func mutualDebtOffsetID(from note: String) -> UUID? {
        markerID(from: note, prefix: mutualDebtOffsetMarkerPrefix)
    }

    static func isManualDebtSettlement(note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix(manualDebtSettlementMarkerPrefix)
    }

    static func manualDebtSettlementMarker(id: UUID) -> String {
        "\(manualDebtSettlementMarkerPrefix)\(id.uuidString)]"
    }

    static func manualDebtSettlementID(from note: String) -> UUID? {
        markerID(from: note, prefix: manualDebtSettlementMarkerPrefix)
    }

    static func repaymentRecordKind(note: String) -> RepaymentRecordKind {
        if let offsetID = mutualDebtOffsetID(from: note) {
            return .mutualDebtOffset(offsetID)
        }
        if isMutualDebtOffset(note: note) {
            return .invalidSpecial
        }
        if let settlementID = manualDebtSettlementID(from: note) {
            return .manualDebtSettlement(settlementID)
        }
        if isManualDebtSettlement(note: note) {
            return .invalidSpecial
        }
        return .ordinary
    }

    private static func markerID(from note: String, prefix: String) -> UUID? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix),
              let closeIndex = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        return UUID(uuidString: String(trimmed[startIndex..<closeIndex]))
    }
}
