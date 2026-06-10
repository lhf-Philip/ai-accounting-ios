import Foundation

enum DebtTransferDirection {
    case borrow
    case repay
}

struct DebtTransferEditDraft {
    let debtAccount: Account
    let ownAccount: Account
    let amount: Decimal
    let currencyCode: String
    let date: Date
    let note: String
    let direction: DebtTransferDirection
}

enum DebtTransferEditError: LocalizedError, Equatable {
    case invalidAmount
    case missingGroup
    case invalidStructure
    case directionChanged

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "債務金額必須大於 0。"
        case .missingGroup:
            return "找不到原本的債務轉帳群組。"
        case .invalidStructure:
            return "債務轉帳必須包含一個借貸對象與一個自己的帳戶。"
        case .directionChanged:
            return "不可在編輯時翻轉借入／還款方向。"
        }
    }
}

enum DebtTransferEditService {
    static func apply(
        _ draft: DebtTransferEditDraft,
        debtTransaction: FinancialTransaction,
        ownTransaction: FinancialTransaction,
        updatedAt: Date
    ) throws {
        guard draft.amount > 0 else {
            throw DebtTransferEditError.invalidAmount
        }
        guard let groupID = debtTransaction.transferGroupID,
              ownTransaction.transferGroupID == groupID
        else {
            throw DebtTransferEditError.missingGroup
        }
        guard debtTransaction.account?.type == .debt,
              ownTransaction.account?.type != .debt
        else {
            throw DebtTransferEditError.invalidStructure
        }

        let existingDebtSide = debtTransaction.transferSide
            ?? (debtTransaction.amount < 0 ? .outgoing : .incoming)
        let expectedDebtSide: TransferSide = draft.direction == .borrow ? .outgoing : .incoming
        guard existingDebtSide == expectedDebtSide else {
            throw DebtTransferEditError.directionChanged
        }

        let amount = abs(draft.amount)
        let currencyCode = draft.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let memo = draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (draft.direction == .borrow ? "借入 / 收款" : "借出 / 還款")
            : draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

        debtTransaction.account = draft.debtAccount
        ownTransaction.account = draft.ownAccount
        debtTransaction.currencyCode = currencyCode
        ownTransaction.currencyCode = currencyCode
        debtTransaction.date = draft.date
        ownTransaction.date = draft.date
        debtTransaction.transferGroupID = groupID
        ownTransaction.transferGroupID = groupID
        debtTransaction.linkedTransactionID = ownTransaction.id
        ownTransaction.linkedTransactionID = debtTransaction.id
        debtTransaction.updatedAt = updatedAt
        ownTransaction.updatedAt = updatedAt

        switch draft.direction {
        case .borrow:
            debtTransaction.amount = -amount
            debtTransaction.transferSide = .outgoing
            debtTransaction.note = "\(memo) (借入至 \(draft.ownAccount.name))"
            ownTransaction.amount = amount
            ownTransaction.transferSide = .incoming
            ownTransaction.note = "\(memo) (來自 \(draft.debtAccount.name))"
        case .repay:
            ownTransaction.amount = -amount
            ownTransaction.transferSide = .outgoing
            ownTransaction.note = "\(memo) (還款給 \(draft.debtAccount.name))"
            debtTransaction.amount = amount
            debtTransaction.transferSide = .incoming
            debtTransaction.note = "\(memo) (來自 \(draft.ownAccount.name))"
        }
    }
}
