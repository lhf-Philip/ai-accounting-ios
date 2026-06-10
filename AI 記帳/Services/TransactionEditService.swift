import Foundation

struct OrdinaryTransactionEditDraft {
    let amount: Decimal
    let currencyCode: String
    let date: Date
    let note: String
    let type: TransactionType
    let account: Account?
    let category: Category?
    let tags: [Tag]
}

struct TransferLegIdentity: Hashable {
    let accountID: UUID
    let currencyCode: String

    init(accountID: UUID, currencyCode: String) {
        self.accountID = accountID
        self.currencyCode = currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

enum TransactionEditError: LocalizedError, Equatable {
    case invalidAmount
    case invalidCurrency
    case missingAccount
    case invalidAccountType

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "請輸入有效金額。"
        case .invalidCurrency:
            return "請選擇有效幣種。"
        case .missingAccount:
            return "請選擇帳戶。"
        case .invalidAccountType:
            return "一般收入或支出只能使用自己的帳戶。"
        }
    }
}

@MainActor
enum TransactionEditService {
    static func validate(_ draft: OrdinaryTransactionEditDraft) throws {
        guard draft.amount > 0 else {
            throw TransactionEditError.invalidAmount
        }

        guard !draft.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransactionEditError.invalidCurrency
        }

        guard let account = draft.account else {
            throw TransactionEditError.missingAccount
        }

        if draft.type != .transfer, account.type == .debt {
            throw TransactionEditError.invalidAccountType
        }
    }

    static func apply(
        _ draft: OrdinaryTransactionEditDraft,
        to transaction: FinancialTransaction,
        updatedAt: Date = Date()
    ) throws {
        try validate(draft)

        transaction.type = draft.type
        transaction.amount = signedAmount(
            draft.amount,
            for: draft.type,
            preservingTransferSignFrom: transaction.amount
        )
        transaction.currencyCode = draft.currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        transaction.date = draft.date
        transaction.note = draft.note
        transaction.account = draft.account
        transaction.category = draft.type == .transfer ? nil : draft.category
        transaction.tags = draft.type == .transfer ? [] : draft.tags
        transaction.updatedAt = updatedAt
    }

    static func hasDuplicateTransferLegs(_ identities: [TransferLegIdentity]) -> Bool {
        Set(identities).count != identities.count
    }

    private static func signedAmount(
        _ amount: Decimal,
        for type: TransactionType,
        preservingTransferSignFrom originalAmount: Decimal
    ) -> Decimal {
        switch type {
        case .expense:
            return -abs(amount)
        case .income:
            return abs(amount)
        case .transfer:
            return originalAmount >= 0 ? abs(amount) : -abs(amount)
        }
    }
}
