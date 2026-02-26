import Foundation
import SwiftData

// MARK: - Enums

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case cash = "Cash"
    case bank = "Bank"
    case creditCard = "Credit Card"
    case debt = "Debt"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .cash: return "現金"
        case .bank: return "銀行"
        case .creditCard: return "信用卡"
        case .debt: return "借貸/債務"
        }
    }
}

enum TransactionType: String, Codable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"
}

enum TransferSide: String, Codable {
    case outgoing = "Outgoing"
    case incoming = "Incoming"
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    case both = "Both"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .both: return "通用"
        }
    }
    
    func supports(_ transactionType: TransactionType) -> Bool {
        switch transactionType {
        case .expense:
            return self == .expense || self == .both
        case .income:
            return self == .income || self == .both
        case .transfer:
            return false
        }
    }
}

// MARK: - Models

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var name: String
    var currency: String
    var type: AccountType
    var baseBalance: Decimal
    var sortOrder: Int
    var isArchived: Bool = false // 🔥 新增：歸檔狀態 (預設不歸檔)
    
    @Relationship(deleteRule: .cascade, inverse: \FinancialTransaction.account)
    var transactions: [FinancialTransaction] = []
    
    init(id: UUID = UUID(), name: String, currency: String, type: AccountType, baseBalance: Decimal, sortOrder: Int = 0, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.currency = currency
        self.type = type
        self.baseBalance = baseBalance
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
    
    var currentBalance: Decimal {
        let transactionSum = transactions.reduce(0) { $0 + $1.amount }
        return baseBalance + transactionSum
    }
}

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var kind: CategoryKind = CategoryKind.both
    
    @Relationship(deleteRule: .nullify, inverse: \FinancialTransaction.category)
    var transactions: [FinancialTransaction] = []
    
    init(id: UUID = UUID(), name: String, icon: String, colorHex: String, kind: CategoryKind = CategoryKind.both) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.kind = kind
    }
}

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    
    @Relationship(deleteRule: .nullify, inverse: \FinancialTransaction.tags)
    var transactions: [FinancialTransaction] = []
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class FinancialTransaction {
    @Attribute(.unique) var id: UUID
    var amount: Decimal
    var currencyCode: String
    var date: Date
    var note: String
    var photoPath: String?
    
    var type: TransactionType
    var linkedTransactionID: UUID?
    var transferGroupID: UUID?
    var transferSide: TransferSide?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var account: Account?
    var category: Category?
    var tags: [Tag] = []
    
    init(id: UUID = UUID(),
         amount: Decimal,
         currencyCode: String = "HKD",
         date: Date = Date(),
         note: String = "",
         photoPath: String? = nil,
         type: TransactionType = .expense,
         linkedTransactionID: UUID? = nil,
         transferGroupID: UUID? = nil,
         transferSide: TransferSide? = nil,
         account: Account? = nil,
         category: Category? = nil,
         tags: [Tag] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.note = note
        self.photoPath = photoPath
        self.type = type
        self.linkedTransactionID = linkedTransactionID
        self.transferGroupID = transferGroupID
        self.transferSide = transferSide
        self.account = account
        self.category = category
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Shortcut {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var amount: Decimal
    var currencyCode: String // 🔥 新增：捷徑的幣種
    var type: TransactionType
    var note: String
    
    var account: Account?
    var category: Category?
    var tags: [Tag] = []
    
    init(id: UUID = UUID(), name: String, icon: String, amount: Decimal, currencyCode: String = "HKD", type: TransactionType, note: String, account: Account? = nil, category: Category? = nil, tags: [Tag] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.amount = amount
        self.currencyCode = currencyCode
        self.type = type
        self.note = note
        self.account = account
        self.category = category
        self.tags = tags
    }
}

@Model
final class CategoryMonthlyBudget {
    @Attribute(.unique) var id: UUID
    var monthKey: String // yyyy-MM
    var amount: Decimal
    var currencyCode: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    
    var category: Category?
    
    init(
        id: UUID = UUID(),
        monthKey: String,
        amount: Decimal,
        currencyCode: String = "HKD",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        category: Category? = nil
    ) {
        self.id = id
        self.monthKey = monthKey
        self.amount = amount
        self.currencyCode = currencyCode
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.category = category
    }
}

@Model
final class AdvanceCase {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var currencyCode: String
    var myShareAmount: Decimal
    var note: String
    var selfExpenseTransactionID: UUID?
    var createdAt: Date
    var updatedAt: Date
    
    var payerAccount: Account?
    var expenseCategory: Category?
    
    @Relationship(deleteRule: .cascade, inverse: \AdvanceParticipant.advanceCase)
    var participants: [AdvanceParticipant] = []
    
    @Relationship(deleteRule: .cascade, inverse: \AdvanceRepayment.advanceCase)
    var repayments: [AdvanceRepayment] = []
    
    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        currencyCode: String = "HKD",
        myShareAmount: Decimal = 0,
        note: String = "",
        selfExpenseTransactionID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        payerAccount: Account? = nil,
        expenseCategory: Category? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.currencyCode = currencyCode
        self.myShareAmount = myShareAmount
        self.note = note
        self.selfExpenseTransactionID = selfExpenseTransactionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.payerAccount = payerAccount
        self.expenseCategory = expenseCategory
    }
}

@Model
final class AdvanceParticipant {
    @Attribute(.unique) var id: UUID
    var name: String
    var owedAmount: Decimal
    var repaidAmount: Decimal
    var initialTransferGroupID: UUID?
    var createdAt: Date
    var updatedAt: Date
    
    var advanceCase: AdvanceCase?
    var debtAccount: Account?
    
    init(
        id: UUID = UUID(),
        name: String,
        owedAmount: Decimal,
        repaidAmount: Decimal = 0,
        initialTransferGroupID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        advanceCase: AdvanceCase? = nil,
        debtAccount: Account? = nil
    ) {
        self.id = id
        self.name = name
        self.owedAmount = owedAmount
        self.repaidAmount = repaidAmount
        self.initialTransferGroupID = initialTransferGroupID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.advanceCase = advanceCase
        self.debtAccount = debtAccount
    }
    
    var remainingAmount: Decimal {
        let remaining = owedAmount - repaidAmount
        return remaining > 0 ? remaining : 0
    }
}

@Model
final class AdvanceRepayment {
    @Attribute(.unique) var id: UUID
    var amount: Decimal
    var currencyCode: String
    var normalizedAmount: Decimal // 換算為 AdvanceCase 幣種
    var date: Date
    var note: String
    var linkedTransferGroupID: UUID?
    var createdAt: Date
    
    var advanceCase: AdvanceCase?
    var participant: AdvanceParticipant?
    var receivedAccount: Account?
    
    init(
        id: UUID = UUID(),
        amount: Decimal,
        currencyCode: String = "HKD",
        normalizedAmount: Decimal,
        date: Date = Date(),
        note: String = "",
        linkedTransferGroupID: UUID? = nil,
        createdAt: Date = Date(),
        advanceCase: AdvanceCase? = nil,
        participant: AdvanceParticipant? = nil,
        receivedAccount: Account? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.normalizedAmount = normalizedAmount
        self.date = date
        self.note = note
        self.linkedTransferGroupID = linkedTransferGroupID
        self.createdAt = createdAt
        self.advanceCase = advanceCase
        self.participant = participant
        self.receivedAccount = receivedAccount
    }
}
