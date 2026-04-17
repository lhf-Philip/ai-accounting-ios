import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @Query(sort: \Shortcut.name) private var shortcuts: [Shortcut] // 查詢捷徑
    @Query(sort: \AdvanceCase.date, order: .reverse) private var advanceCases: [AdvanceCase]
    @Query private var advanceParticipants: [AdvanceParticipant]
    @Query private var advanceRepayments: [AdvanceRepayment]
    
    @State private var filterType: FilterType = .month
    @State private var selectedDate: Date = Date()
    @State private var showingFilterSheet = false
    @State private var searchText = ""
    
    @State private var transactionToEdit: FinancialTransaction?
    
    // 捷徑相關
    @State private var showingAddShortcut = false
    @State private var pendingShortcut: Shortcut? // 待確認的捷徑
    @State private var showingShortcutConfirm = false
    @State private var shortcutToDelete: Shortcut?
    @State private var showingShortcutDeleteConfirm = false

    enum LedgerItem: Identifiable {
        case transaction(FinancialTransaction)
        case advanceCaseSummary(AdvanceCase)

        var id: String {
            switch self {
            case .transaction(let transaction):
                return "transaction-\(transaction.id.uuidString)"
            case .advanceCaseSummary(let advanceCase):
                return "advance-\(advanceCase.id.uuidString)"
            }
        }

        var date: Date {
            switch self {
            case .transaction(let transaction):
                return transaction.date
            case .advanceCaseSummary(let advanceCase):
                return advanceCase.date
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. 日期選擇器 (固定)
                HStack {
                    Spacer()
                    Button(action: { showingFilterSheet = true }) {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            Text(filterDisplayString).bold()
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))

                Divider()

                // MARK: - 2. 捷徑列 (Shortcuts Bar)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // 新增按鈕
                        Button(action: { showingAddShortcut = true }) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .frame(width: 44, height: 44)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Circle())
                                Text("捷徑")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // 捷徑列表
                        ForEach(shortcuts) { shortcut in
                            shortcutTile(shortcut)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(uiColor: .systemBackground))
                
                Divider()
                
                // MARK: - 3. 列表內容 (List)
                List {
                    // 交易分組
                    ForEach(groupedTransactions, id: \.title) { group in
                        Section(header: Text(group.title)) {
                            ForEach(group.items) { item in
                                switch item {
                                case .transaction(let transaction):
                                    TransactionRow(
                                        transaction: transaction,
                                        transferCounterpart: transferCounterpartByID[transaction.id]
                                    )
                                        .onTapGesture {
                                            transactionToEdit = transaction
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) { deleteTransaction(transaction) } label: { Label("刪除", systemImage: "trash") }
                                            Button {
                                                transactionToEdit = transaction
                                            } label: { Label("編輯", systemImage: "pencil") }.tint(.blue)
                                        }
                                case .advanceCaseSummary(let advanceCase):
                                    NavigationLink(destination: AdvanceCaseDetailView(advanceCase: advanceCase)) {
                                        AdvanceCaseSummaryRow(advanceCase: advanceCase)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .prominentInlineTitle("帳目明細")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜尋備註、分類、金額")
            .sheet(isPresented: $showingFilterSheet) {
                DateFilterView(filterType: $filterType, selectedDate: $selectedDate)
            }
            .sheet(isPresented: $showingAddShortcut) {
                AddShortcutView()
            }
            .sheet(item: $transactionToEdit) { tx in
                if tx.type == .transfer {
                    if isAdvanceTransfer(tx) {
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
            .overlay {
                if filteredLedgerItems.isEmpty {
                    ContentUnavailableView("無交易紀錄", systemImage: "list.bullet.clipboard", description: Text("該區間或搜尋條件下無資料"))
                }
            }
            // 捷徑確認彈窗
            .alert("確認快速記帳？", isPresented: $showingShortcutConfirm) {
                Button("確認", role: .none) { executeShortcut() }
                Button("取消", role: .cancel) { }
            } message: {
                if let sc = pendingShortcut {
                    Text("\(sc.name)\n\(sc.type == .expense ? "支出" : "收入") \(sc.amount.formatted()) \(sc.account?.currency ?? "")")
                }
            }
            .confirmationDialog(
                "刪除捷徑？",
                isPresented: $showingShortcutDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("刪除", role: .destructive) {
                    if let shortcut = shortcutToDelete {
                        modelContext.delete(shortcut)
                    }
                    shortcutToDelete = nil
                }
                Button("取消", role: .cancel) {
                    shortcutToDelete = nil
                }
            } message: {
                Text(shortcutToDelete?.name ?? "")
            }
        }
    }
    
    @ViewBuilder
    private func shortcutTile(_ shortcut: Shortcut) -> some View {
        let tapGesture = TapGesture().onEnded {
            pendingShortcut = shortcut
            showingShortcutConfirm = true
        }
        let longPressGesture = LongPressGesture(minimumDuration: 0.6).onEnded { _ in
            shortcutToDelete = shortcut
            showingShortcutDeleteConfirm = true
        }
        
        VStack(spacing: 4) {
            Text(shortcut.icon)
                .font(.title)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(shortcut.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
        .gesture(longPressGesture.exclusively(before: tapGesture))
        .accessibilityHint("點按執行，長按可刪除捷徑")
    }
    
    // MARK: - Logic
    
    private var transferCounterpartByID: [UUID: TransferCounterpartInfo] {
        TransferPresentationService.counterpartMap(transactions: transactions)
    }
    
    private func executeShortcut() {
        guard let sc = pendingShortcut, let account = sc.account else { return }
        
        let finalAmount = (sc.type == .expense) ? -abs(sc.amount) : abs(sc.amount)
        
        // 🔥 修改：使用捷徑設定的幣種，而非帳戶預設幣種
        let currency = sc.currencyCode
        
        let tx = FinancialTransaction(
            amount: finalAmount,
            currencyCode: currency, // 🔥 這裡
            date: Date(),
            note: sc.note.isEmpty ? sc.name : sc.note,
            type: sc.type,
            account: account,
            category: sc.category,
            tags: sc.tags
        )
        modelContext.insert(tx)
        print("✅ 捷徑執行成功: \(sc.name) (\(currency))")
    }
    
    // ... Helpers (Filter logic 同前，省略重複代碼以節省篇幅) ...
    // 請保留原本的 filterDisplayString, filteredTransactions, groupedTransactions
    // calculateTotalEstimate, calculateCurrencyBreakdown, deleteTransaction
    // 注意：在 calculateCurrencyBreakdown 中，需使用 tx.currencyCode 替代舊的 tx.account.currency
    
    var filterDisplayString: String {
        let formatter = DateFormatter()
        switch filterType {
        case .all: return "全部紀錄"
        case .year: return "\(Calendar.current.component(.year, from: selectedDate))年"
        case .month: formatter.dateFormat = "yyyy年 M月"; return formatter.string(from: selectedDate)
        case .day: formatter.dateFormat = "M月d日"; return formatter.string(from: selectedDate)
        }
    }
    
    var filteredTransactions: [FinancialTransaction] {
        let calendar = Calendar.current
        let timeFiltered = transactions.filter { tx in
            if tx.type == .transfer && tx.amount > 0 && !TransactionSemantics.isDebtForgiveness(note: tx.note) { return false }
            if tx.type == .transfer,
               tx.transferGroupID == nil,
               tx.linkedTransactionID == nil,
               isAssetAdjustment(note: tx.note) {
                return false
            }
            if let groupID = tx.transferGroupID, initialAdvanceGroupIDs.contains(groupID) {
                return false
            }
            switch filterType {
            case .all: return true
            case .year: return calendar.isDate(tx.date, equalTo: selectedDate, toGranularity: .year)
            case .month: return calendar.isDate(tx.date, equalTo: selectedDate, toGranularity: .month)
            case .day: return calendar.isDate(tx.date, equalTo: selectedDate, toGranularity: .day)
            }
        }
        let searched = searchText.isEmpty ? timeFiltered : timeFiltered.filter { tx in
            tx.note.localizedCaseInsensitiveContains(searchText) ||
            (tx.category?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
            tx.tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) } ||
            String(describing: abs(tx.amount)).contains(searchText)
        }
        return collapseTransferGroups(in: searched)
    }

    var filteredAdvanceCases: [AdvanceCase] {
        let calendar = Calendar.current
        let timeFiltered = advanceCases.filter { advanceCase in
            switch filterType {
            case .all: return true
            case .year: return calendar.isDate(advanceCase.date, equalTo: selectedDate, toGranularity: .year)
            case .month: return calendar.isDate(advanceCase.date, equalTo: selectedDate, toGranularity: .month)
            case .day: return calendar.isDate(advanceCase.date, equalTo: selectedDate, toGranularity: .day)
            }
        }

        guard !searchText.isEmpty else {
            return timeFiltered
        }

        return timeFiltered.filter { advanceCase in
            advanceCase.title.localizedCaseInsensitiveContains(searchText)
                || advanceCase.note.localizedCaseInsensitiveContains(searchText)
                || (advanceCase.payerAccount?.name.localizedCaseInsensitiveContains(searchText) ?? false)
                || advanceCase.participants.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var filteredLedgerItems: [LedgerItem] {
        (filteredTransactions.map(LedgerItem.transaction) + filteredAdvanceCases.map(LedgerItem.advanceCaseSummary))
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.id > rhs.id
                }
                return lhs.date > rhs.date
            }
    }

    struct TransactionGroup { let title: String; let items: [LedgerItem] }

    var groupedTransactions: [TransactionGroup] {
        let formatter = DateFormatter()
        let grouping: (Date) -> String = { date in
            switch filterType {
            case .all: formatter.dateFormat = "yyyy年"; return formatter.string(from: date)
            case .year: formatter.dateFormat = "M月"; return formatter.string(from: date)
            case .month: formatter.dateFormat = "d日 (EEEE)"; return formatter.string(from: date)
            case .day: return "明細"
            }
        }
        let groupedDict = Dictionary(grouping: filteredLedgerItems) { item in grouping(item.date) }
        let sortedKeys = groupedDict.keys.sorted { title1, title2 in
            guard let item1 = groupedDict[title1]?.first, let item2 = groupedDict[title2]?.first else { return title1 > title2 }
            return item1.date > item2.date
        }
        return sortedKeys.map { TransactionGroup(title: $0, items: groupedDict[$0] ?? []) }
    }
    
    func calculateTotalEstimate() -> String {
        var total: Decimal = 0
        for tx in filteredTransactions {
            if tx.type == .transfer { continue }
            // 🔥 使用交易本身的 currencyCode
            let converted = CurrencyService.shared.convert(amount: tx.amount, from: tx.currencyCode)
            total += converted
        }
        return total.formatted(.currency(code: CurrencyService.shared.mainCurrency))
    }
    
    struct CurrencyTotal { let currency: String; let amount: Decimal }
    
    func calculateCurrencyBreakdown() -> [CurrencyTotal] {
        let validTransactions = filteredTransactions.filter { $0.type != .transfer }
        // 🔥 使用交易本身的 currencyCode 分組
        let grouped = Dictionary(grouping: validTransactions) { $0.currencyCode }
        return grouped.map { (curr, txs) in
            CurrencyTotal(currency: curr, amount: txs.reduce(0) { $0 + $1.amount })
        }.sorted { $0.currency < $1.currency }
    }
    
    private func deleteTransaction(_ tx: FinancialTransaction) {
        if tx.type == .transfer, let groupID = tx.transferGroupID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            if let groupedTransfers = try? modelContext.fetch(descriptor) {
                for transfer in groupedTransfers {
                    modelContext.delete(transfer)
                }
                return
            }
        }
        
        if tx.type == .transfer, let linkedID = tx.linkedTransactionID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.id == linkedID }
            )
            if let linked = try? modelContext.fetch(descriptor).first {
                modelContext.delete(linked)
            }
        }
        modelContext.delete(tx)
    }
    
    private var advanceGroupIDs: Set<UUID> {
        var ids = Set<UUID>(advanceParticipants.compactMap(\.initialTransferGroupID))
        ids.formUnion(advanceRepayments.compactMap(\.linkedTransferGroupID))
        return ids
    }

    private var initialAdvanceGroupIDs: Set<UUID> {
        Set(advanceParticipants.compactMap(\.initialTransferGroupID))
    }

    private func isAdvanceTransfer(_ tx: FinancialTransaction) -> Bool {
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
    
    private func collapseTransferGroups(in items: [FinancialTransaction]) -> [FinancialTransaction] {
        let representatives = Dictionary(grouping: items.compactMap { tx -> (UUID, FinancialTransaction)? in
            guard let groupID = tx.transferGroupID else { return nil }
            return (groupID, tx)
        }, by: { $0.0 }).compactMapValues { entries in
            let transfers = entries.map { $0.1 }
            return transfers.first(where: { $0.transferSide == .outgoing })
                ?? transfers.first(where: { $0.amount < 0 })
                ?? transfers.first
        }
        
        var seenGroupIDs = Set<UUID>()
        var output: [FinancialTransaction] = []
        
        for tx in items {
            guard tx.type == .transfer, let groupID = tx.transferGroupID else {
                output.append(tx)
                continue
            }
            
            if seenGroupIDs.contains(groupID) {
                continue
            }
            seenGroupIDs.insert(groupID)
            output.append(representatives[groupID] ?? tx)
        }
        
        return output
    }
    
    private func isAssetAdjustment(note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(TransactionSemantics.assetAdjustmentMarker)
    }
}

private struct AdvanceCaseSummaryRow: View {
    let advanceCase: AdvanceCase

    private var totalAmount: Decimal {
        AdvanceService.totalAdvanced(for: advanceCase)
    }

    private var outstandingAmount: Decimal {
        AdvanceService.outstandingAmount(for: advanceCase)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(advanceCase.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(advanceCase.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(totalAmount.formatted(.currency(code: advanceCase.currencyCode)))
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("未清 \(outstandingAmount.formatted(.currency(code: advanceCase.currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var summaryLine: String {
        let payer = advanceCase.payerAccount?.name ?? "未指定付款帳戶"
        return "\(advanceCase.participants.count) 人 · \(payer)"
    }
}
