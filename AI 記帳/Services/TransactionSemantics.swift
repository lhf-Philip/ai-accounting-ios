import Foundation

enum DebtForgivenessDirection: String, CaseIterable, Identifiable {
    case forgivenByOthers = "別人免除我欠的"
    case forgiveOthers = "我免除別人欠我的"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .forgivenByOthers:
            return "這會減少你對對方的負債，不計入收入。"
        case .forgiveOthers:
            return "這會減少對方欠你的金額，不計入收入。"
        }
    }

    var amountSign: Decimal {
        switch self {
        case .forgivenByOthers:
            return 1
        case .forgiveOthers:
            return -1
        }
    }

    var displayTitle: String {
        switch self {
        case .forgivenByOthers:
            return "免除債務（對方免除）"
        case .forgiveOthers:
            return "免除債務（我方免除）"
        }
    }
}

enum RateSourceState: String {
    case live
    case cached
    case unavailable

    var label: String {
        switch self {
        case .live:
            return "即時匯率"
        case .cached:
            return "上次匯率"
        case .unavailable:
            return "暫無匯率"
        }
    }
}

enum TransactionSemantics {
    static let debtForgivenessMarker = "[免除債務]"
    static let assetAdjustmentMarker = "[資產調整]"

    static func ownAccounts(from accounts: [Account]) -> [Account] {
        accounts.filter { $0.type != .debt && !$0.isArchived }
    }

    static func debtAccounts(from accounts: [Account]) -> [Account] {
        accounts.filter { $0.type == .debt && !$0.isArchived }
    }

    static func allowedAccounts(for type: TransactionType, from accounts: [Account]) -> [Account] {
        switch type {
        case .income:
            return ownAccounts(from: accounts)
        case .expense:
            return ownAccounts(from: accounts)
        case .transfer:
            return accounts.filter { !$0.isArchived }
        }
    }

    static func isDebtForgiveness(note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(debtForgivenessMarker)
    }

    static func debtForgivenessDirection(note: String) -> DebtForgivenessDirection? {
        guard isDebtForgiveness(note: note) else { return nil }
        if note.contains("對方免除") { return .forgivenByOthers }
        if note.contains("我方免除") { return .forgiveOthers }
        return nil
    }

    static func debtForgivenessNote(baseNote: String, debtAccountName: String, direction: DebtForgivenessDirection) -> String {
        let trimmed = baseNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix: String
        switch direction {
        case .forgivenByOthers:
            suffix = "(對方免除：\(debtAccountName))"
        case .forgiveOthers:
            suffix = "(我方免除：\(debtAccountName))"
        }

        if trimmed.isEmpty {
            return "\(debtForgivenessMarker) \(suffix)"
        }
        return "\(debtForgivenessMarker) \(trimmed) \(suffix)"
    }

    static func debtForgivenessDisplayTitle(note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDebtForgiveness(note: trimmed) else { return trimmed }

        let withoutMarker = trimmed
            .replacingOccurrences(of: debtForgivenessMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if withoutMarker.isEmpty {
            return "免除債務"
        }
        return withoutMarker
    }

    static func isLegacyDebtIncome(_ transaction: FinancialTransaction) -> Bool {
        transaction.type == .income && transaction.account?.type == .debt
    }

    static func isLegacyDebtIncome(_ shortcut: Shortcut) -> Bool {
        shortcut.type == .income && shortcut.account?.type == .debt
    }
}
