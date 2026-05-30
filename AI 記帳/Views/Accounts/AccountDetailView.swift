import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var allTransactions: [FinancialTransaction]
    @Query private var advanceParticipants: [AdvanceParticipant]
    @Query private var advanceRepayments: [AdvanceRepayment]
    @Environment(\.modelContext) private var modelContext
    @State private var transactionToEdit: FinancialTransaction?
    @State private var deletionErrorMessage: String?
    
    // 🔥 修正 1：定義一個結構體來代替 Tuple，讓 ForEach 能識別
    struct CurrencyBalance: Identifiable {
        var id: String { currency } // 使用幣種作為唯一 ID
        let currency: String
        let amount: Decimal
    }
    
    var body: some View {
        let renderState = AccountDetailRenderState(
            account: account,
            allTransactions: allTransactions,
            advanceParticipants: advanceParticipants,
            advanceRepayments: advanceRepayments
        )

        List {
            // 1. 頂部資訊卡 (總覽)
            Section {
                VStack(spacing: 16) {
                    
                    if renderState.currencyBalances.isEmpty {
                        // 如果剛好歸零，顯示 0 (預設幣種)
                        Text(Decimal(0).formatted(.currency(code: account.currency)))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else {
                        // 🔥 修正 3：現在 ForEach 可以正常運作了
                        ForEach(renderState.currencyBalances) { item in
                            HStack {
                                Text(item.currency)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)
                                
                                Spacer()
                                
                                Text(item.amount.formatted(.currency(code: item.currency)))
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(item.amount >= 0 ? Color.primary : Color.red)
                            }
                            
                            // 分隔線邏輯：如果不是最後一個，顯示分隔線
                            if item.id != renderState.currencyBalances.last?.id {
                                Divider()
                            }
                        }
                    }

                    HStack {
                        Text(account.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text(account.type.displayName)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 10)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color(uiColor: .systemGroupedBackground))
            }
            
            // 2. 交易列表
            Section("交易紀錄") {
                ForEach(renderState.accountTransactions) { transaction in
                    TransactionRow(
                        transaction: transaction,
                        transferCounterpart: renderState.transferCounterpartByID[transaction.id]
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        transactionToEdit = transaction
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTransaction(transaction)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }

                        Button {
                            transactionToEdit = transaction
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $transactionToEdit) { tx in
            transactionEditor(for: tx, renderState: renderState)
        }
        .alert("無法刪除", isPresented: Binding(
            get: { deletionErrorMessage != nil },
            set: { if !$0 { deletionErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "")
        }
    }
    
    @ViewBuilder
    private func transactionEditor(for tx: FinancialTransaction, renderState: AccountDetailRenderState) -> some View {
        if tx.type == .transfer {
            if isAdvanceTransfer(tx, advanceGroupIDs: renderState.advanceGroupIDs) {
                EditAdvanceTransferView(originalTransaction: tx)
            } else if TransactionSemantics.isDebtForgiveness(note: tx.note) {
                AddDebtView(existingForgivenessTransaction: tx)
            } else {
                EditTransferView(originalTransaction: tx)
            }
        } else {
            EditTransactionView(transaction: tx)
        }
    }

    private func isAdvanceTransfer(_ tx: FinancialTransaction, advanceGroupIDs: Set<UUID>) -> Bool {
        guard tx.type == .transfer else { return false }
        if let groupID = tx.transferGroupID, advanceGroupIDs.contains(groupID) {
            return true
        }
        let compacted = tx.note.replacingOccurrences(of: " ", with: "")
        return compacted.contains("(代墊給")
            || compacted.contains("(代墊給我")
            || compacted.contains("(還款至")
            || compacted.contains("(還款給")
    }

    private func deleteTransaction(_ transaction: FinancialTransaction) {
        do {
            try LedgerDeletionService.delete(transaction: transaction, modelContext: modelContext)
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }
}

private struct AccountDetailRenderState {
    let accountTransactions: [FinancialTransaction]
    let transferCounterpartByID: [UUID: TransferCounterpartInfo]
    let currencyBalances: [AccountDetailView.CurrencyBalance]
    let advanceGroupIDs: Set<UUID>

    init(
        account: Account,
        allTransactions: [FinancialTransaction],
        advanceParticipants: [AdvanceParticipant],
        advanceRepayments: [AdvanceRepayment]
    ) {
        let accountTransactions = allTransactions.filter { $0.account?.id == account.id }
        var advanceGroupIDs = Set(advanceParticipants.compactMap(\.initialTransferGroupID))
        advanceGroupIDs.formUnion(advanceRepayments.compactMap(\.linkedTransferGroupID))

        self.accountTransactions = accountTransactions
        self.advanceGroupIDs = advanceGroupIDs
        self.transferCounterpartByID = TransferPresentationService.counterpartMap(transactions: allTransactions)
        self.currencyBalances = Self.currencyBalances(
            account: account,
            accountTransactions: accountTransactions
        )
    }

    private static func currencyBalances(
        account: Account,
        accountTransactions: [FinancialTransaction]
    ) -> [AccountDetailView.CurrencyBalance] {
        var balances: [String: Decimal] = [:]

        if account.baseBalance != 0 {
            balances[account.currency, default: 0] += account.baseBalance
        }

        for tx in accountTransactions {
            balances[tx.currencyCode, default: 0] += tx.amount
        }

        return balances
            .filter { $0.value != 0 }
            .map { AccountDetailView.CurrencyBalance(currency: $0.key, amount: $0.value) }
            .sorted { $0.currency < $1.currency }
    }
}
