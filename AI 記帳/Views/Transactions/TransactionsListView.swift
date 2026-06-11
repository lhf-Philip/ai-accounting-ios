import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @Query(sort: \Shortcut.name) private var shortcuts: [Shortcut] // 查詢捷徑
    @Query(sort: \AdvanceCase.date, order: .reverse) private var advanceCases: [AdvanceCase]
    @Query private var advanceParticipants: [AdvanceParticipant]
    @Query private var advanceRepayments: [AdvanceRepayment]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    @AppStorage(DateFilterPreferenceKeys.filterType) private var filterTypeRaw: String = FilterType.month.rawValue
    @AppStorage(DateFilterPreferenceKeys.selectedDate) private var selectedDateTimeInterval: Double = Date().timeIntervalSince1970
    @AppStorage(DateFilterPreferenceKeys.customStartDate) private var customStartDateTimeInterval: Double = Date().timeIntervalSince1970
    @AppStorage(DateFilterPreferenceKeys.customEndDate) private var customEndDateTimeInterval: Double = Date().timeIntervalSince1970
    @State private var showingFilterSheet = false
    @State private var searchText = ""
    @AppStorage("pinLedgerControls") private var pinLedgerControls: Bool = true
    
    @State private var transactionToEdit: FinancialTransaction?
    
    // 捷徑相關
    @State private var showingAddShortcut = false
    @State private var pendingShortcut: Shortcut? // 待確認的捷徑
    @State private var showingShortcutConfirm = false
    @State private var shortcutToDelete: Shortcut?
    @State private var showingShortcutDeleteConfirm = false
    @State private var deletionErrorMessage: String?

    enum LedgerItem: Identifiable {
        case transaction(FinancialTransaction)
        case advanceCaseSummary(AdvanceCaseLedgerSummary)

        var id: String {
            switch self {
            case .transaction(let transaction):
                return "transaction-\(transaction.id.uuidString)"
            case .advanceCaseSummary(let summary):
                return "advance-\(summary.advanceCase.id.uuidString)"
            }
        }

        var date: Date {
            switch self {
            case .transaction(let transaction):
                return transaction.date
            case .advanceCaseSummary(let summary):
                return summary.activityDate
            }
        }
    }

    struct TransactionGroup {
        let title: String
        let items: [LedgerItem]
    }
    
    var body: some View {
        let renderState = makeRenderState()

        NavigationStack {
            ledgerContent(renderState: renderState)
        }
        .sheet(isPresented: $showingFilterSheet) {
            DateFilterView(
                filterType: filterTypeBinding,
                selectedDate: selectedDateBinding,
                customStartDate: customStartDateBinding,
                customEndDate: customEndDateBinding
            )
        }
        .sheet(isPresented: $showingAddShortcut) {
            AddShortcutView()
        }
        .sheet(item: $transactionToEdit) { tx in
            transactionEditor(for: tx, renderState: renderState)
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
    private func ledgerContent(renderState: TransactionsRenderState) -> some View {
        Group {
            if pinLedgerControls {
                VStack(spacing: 0) {
                    pinnedLedgerControls
                    ledgerList(renderState: renderState, includeScrollableControls: false)
                }
            } else {
                ledgerList(renderState: renderState, includeScrollableControls: true)
            }
        }
        .prominentInlineTitle("帳目明細")
        .modifier(LedgerSearchModifier(isEnabled: pinLedgerControls, text: $searchText))
    }

    @ViewBuilder
    private func transactionEditor(for tx: FinancialTransaction, renderState: TransactionsRenderState) -> some View {
        let group = TransferEditRoutingService.groupTransactions(
            for: tx,
            in: renderState.allTransactions
        )
        switch TransferEditRoutingService.classify(
            transaction: tx,
            groupTransactions: group,
            advanceSelfExpenseTransactionIDs: Set(advanceCases.compactMap(\.selfExpenseTransactionID)),
            advanceInitialGroupIDs: renderState.initialAdvanceGroupIDs,
            advanceRepaymentGroupIDs: renderState.repaymentAdvanceGroupIDs
        ) {
        case .advanceSelfExpense, .advanceInitial, .advanceRepayment:
            EditAdvanceTransferView(originalTransaction: tx)
        case .debtForgiveness:
            AddDebtView(existingForgivenessTransaction: tx)
        case .debt:
            AddDebtView(existingDebtTransaction: tx)
        case .ordinary:
            if tx.type == .transfer {
                EditTransferView(originalTransaction: tx)
            } else {
                EditTransactionView(transaction: tx)
            }
        }
    }

    private var pinnedLedgerControls: some View {
        VStack(spacing: 0) {
            dateFilterControl
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))

            Divider()

            shortcutsBar
                .background(Color(uiColor: .systemBackground))

            Divider()
        }
    }

    private func ledgerList(renderState: TransactionsRenderState, includeScrollableControls: Bool) -> some View {
        List {
            if includeScrollableControls {
                Section {
                    dateFilterControl
                    shortcutsBar
                    inlineSearchField
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if renderState.ledgerItems.isEmpty {
                Section {
                    ContentUnavailableView("無交易紀錄", systemImage: "list.bullet.clipboard", description: Text("該區間或搜尋條件下無資料"))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(renderState.groupedTransactions, id: \.title) { group in
                Section(header: Text(group.title)) {
                    ForEach(group.items) { item in
                        switch item {
                        case .transaction(let transaction):
                            TransactionRow(
                                transaction: transaction,
                                transferCounterpart: renderState.transferCounterpartByID[transaction.id]
                            )
                            .accessibilityIdentifier("ledger.transaction.row")
                            .accessibilityValue(transaction.note)
                            .onTapGesture {
                                transactionToEdit = transaction
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleteTransaction(transaction) } label: { Label("刪除", systemImage: "trash") }
                                Button {
                                    transactionToEdit = transaction
                                } label: { Label("編輯", systemImage: "pencil") }.tint(.blue)
                            }
                        case .advanceCaseSummary(let summary):
                            NavigationLink(destination: AdvanceCaseDetailView(advanceCase: summary.advanceCase)) {
                                AdvanceCaseSummaryRow(summary: summary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("ledger.list")
    }

    private var dateFilterControl: some View {
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
            .accessibilityIdentifier("ledger.dateFilter.button")
            Spacer()
        }
    }

    private var shortcutsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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

                ForEach(shortcuts) { shortcut in
                    shortcutTile(shortcut)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var inlineSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜尋備註、分類、金額", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
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
    
    private func makeRenderState() -> TransactionsRenderState {
        TransactionsRenderState(
            transactions: transactions,
            advanceCases: advanceCases,
            advanceParticipants: advanceParticipants,
            advanceRepayments: advanceRepayments,
            tags: tags,
            filterType: filterType,
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            searchText: searchText
        )
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
    
    var filterDisplayString: String {
        filterType.displayString(
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            allTitle: "全部紀錄"
        )
    }

    private var filterType: FilterType {
        FilterType(rawValue: filterTypeRaw) ?? .month
    }

    private var selectedDate: Date {
        Date(timeIntervalSince1970: selectedDateTimeInterval)
    }

    private var customStartDate: Date {
        Date(timeIntervalSince1970: customStartDateTimeInterval)
    }

    private var customEndDate: Date {
        Date(timeIntervalSince1970: customEndDateTimeInterval)
    }

    private var filterTypeBinding: Binding<FilterType> {
        Binding(
            get: { FilterType(rawValue: filterTypeRaw) ?? .month },
            set: { filterTypeRaw = $0.rawValue }
        )
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: selectedDateTimeInterval) },
            set: { selectedDateTimeInterval = $0.timeIntervalSince1970 }
        )
    }

    private var customStartDateBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: customStartDateTimeInterval) },
            set: { customStartDateTimeInterval = $0.timeIntervalSince1970 }
        )
    }

    private var customEndDateBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: customEndDateTimeInterval) },
            set: { customEndDateTimeInterval = $0.timeIntervalSince1970 }
        )
    }
    
    func calculateTotalEstimate() -> String {
        var total: Decimal = 0
        for tx in makeRenderState().filteredTransactions {
            if tx.type == .transfer { continue }
            // 🔥 使用交易本身的 currencyCode
            let converted = CurrencyService.shared.convert(amount: tx.amount, from: tx.currencyCode)
            total += converted
        }
        return total.formatted(.currency(code: CurrencyService.shared.mainCurrency))
    }
    
    struct CurrencyTotal { let currency: String; let amount: Decimal }
    
    func calculateCurrencyBreakdown() -> [CurrencyTotal] {
        let validTransactions = makeRenderState().filteredTransactions.filter { $0.type != .transfer }
        // 🔥 使用交易本身的 currencyCode 分組
        let grouped = Dictionary(grouping: validTransactions) { $0.currencyCode }
        return grouped.map { (curr, txs) in
            CurrencyTotal(currency: curr, amount: txs.reduce(0) { $0 + $1.amount })
        }.sorted { $0.currency < $1.currency }
    }
    
    private func deleteTransaction(_ tx: FinancialTransaction) {
        do {
            try LedgerDeletionService.delete(transaction: tx, modelContext: modelContext)
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }
    
}

private struct TransactionsRenderState {
    let allTransactions: [FinancialTransaction]
    let filteredTransactions: [FinancialTransaction]
    let filteredAdvanceCases: [AdvanceCaseLedgerSummary]
    let ledgerItems: [TransactionsListView.LedgerItem]
    let groupedTransactions: [TransactionsListView.TransactionGroup]
    let transferCounterpartByID: [UUID: TransferCounterpartInfo]
    let initialAdvanceGroupIDs: Set<UUID>
    let repaymentAdvanceGroupIDs: Set<UUID>

    init(
        transactions: [FinancialTransaction],
        advanceCases: [AdvanceCase],
        advanceParticipants: [AdvanceParticipant],
        advanceRepayments: [AdvanceRepayment],
        tags: [Tag],
        filterType: FilterType,
        selectedDate: Date,
        customStartDate: Date,
        customEndDate: Date,
        searchText: String
    ) {
        let initialAdvanceGroupIDs = Set(advanceParticipants.compactMap(\.initialTransferGroupID))
        let repaymentAdvanceGroupIDs = Set(advanceRepayments.compactMap(\.linkedTransferGroupID))
        let advanceSelfExpenseTransactionIDs = Set(advanceCases.compactMap(\.selfExpenseTransactionID))

        let filteredTransactions = Self.filteredTransactions(
            from: transactions,
            initialAdvanceGroupIDs: initialAdvanceGroupIDs,
            repaymentAdvanceGroupIDs: repaymentAdvanceGroupIDs,
            advanceSelfExpenseTransactionIDs: advanceSelfExpenseTransactionIDs,
            filterType: filterType,
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            searchText: searchText
        )
        let filteredAdvanceCases = Self.filteredAdvanceCases(
            from: advanceCases,
            transactions: transactions,
            tags: tags,
            filterType: filterType,
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            searchText: searchText
        )
        let ledgerItems = Self.ledgerItems(
            transactions: filteredTransactions,
            advanceCases: filteredAdvanceCases
        )

        self.allTransactions = transactions
        self.filteredTransactions = filteredTransactions
        self.filteredAdvanceCases = filteredAdvanceCases
        self.ledgerItems = ledgerItems
        self.groupedTransactions = Self.groupedTransactions(from: ledgerItems, filterType: filterType)
        self.transferCounterpartByID = TransferPresentationService.counterpartMap(transactions: transactions)
        self.initialAdvanceGroupIDs = initialAdvanceGroupIDs
        self.repaymentAdvanceGroupIDs = repaymentAdvanceGroupIDs
    }

    private static func filteredTransactions(
        from transactions: [FinancialTransaction],
        initialAdvanceGroupIDs: Set<UUID>,
        repaymentAdvanceGroupIDs: Set<UUID>,
        advanceSelfExpenseTransactionIDs: Set<UUID>,
        filterType: FilterType,
        selectedDate: Date,
        customStartDate: Date,
        customEndDate: Date,
        searchText: String
    ) -> [FinancialTransaction] {
        let timeFiltered = transactions.filter { tx in
            if tx.advanceCaseID != nil || advanceSelfExpenseTransactionIDs.contains(tx.id) {
                return false
            }
            if tx.type == .transfer && tx.amount > 0 && !TransactionSemantics.isDebtForgiveness(note: tx.note) { return false }
            if tx.type == .transfer,
               tx.transferGroupID == nil,
               tx.linkedTransactionID == nil,
               isAssetAdjustment(note: tx.note) {
                return false
            }
            if let groupID = tx.transferGroupID,
               initialAdvanceGroupIDs.contains(groupID) || repaymentAdvanceGroupIDs.contains(groupID) {
                return false
            }
            return filterType.matches(
                date: tx.date,
                selectedDate: selectedDate,
                customStartDate: customStartDate,
                customEndDate: customEndDate
            )
        }
        let searched = searchText.isEmpty ? timeFiltered : timeFiltered.filter { tx in
            tx.note.localizedCaseInsensitiveContains(searchText) ||
            (tx.category?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
            tx.tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) } ||
            String(describing: abs(tx.amount)).contains(searchText)
        }
        return collapseTransferGroups(in: searched)
    }

    private static func filteredAdvanceCases(
        from advanceCases: [AdvanceCase],
        transactions: [FinancialTransaction],
        tags: [Tag],
        filterType: FilterType,
        selectedDate: Date,
        customStartDate: Date,
        customEndDate: Date,
        searchText: String
    ) -> [AdvanceCaseLedgerSummary] {
        let transactionsByCaseID = Dictionary(
            grouping: transactions.compactMap { transaction in
                transaction.advanceCaseID.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }
        let transactionsByGroupID = Dictionary(
            grouping: transactions.compactMap { transaction in
                transaction.transferGroupID.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }
        let transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let tagNameByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })

        return advanceCases.compactMap { advanceCase in
            var caseTransactions = transactionsByCaseID[advanceCase.id] ?? []
            let legacyGroupIDs = Set(
                advanceCase.participants.compactMap(\.initialTransferGroupID)
                    + advanceCase.repayments.compactMap(\.linkedTransferGroupID)
            )
            caseTransactions += legacyGroupIDs.flatMap {
                transactionsByGroupID[$0] ?? []
            }
            if let selfExpenseID = advanceCase.selfExpenseTransactionID,
               let selfExpense = transactionByID[selfExpenseID] {
                caseTransactions.append(selfExpense)
            }
            caseTransactions = Array(
                Dictionary(uniqueKeysWithValues: caseTransactions.map { ($0.id, $0) }).values
            )
            let activityDates = [advanceCase.date]
                + advanceCase.repayments.map(\.date)
                + caseTransactions.map(\.date)
            let matchingDates = activityDates.filter {
                filterType.matches(
                    date: $0,
                    selectedDate: selectedDate,
                    customStartDate: customStartDate,
                    customEndDate: customEndDate
                )
            }
            guard let activityDate = matchingDates.max() else { return nil }

            if !searchText.isEmpty {
                let searchableValues = [
                    advanceCase.title,
                    advanceCase.note,
                    advanceCase.payerAccount?.name ?? "",
                    advanceCase.expenseCategory?.name ?? "",
                    advanceCase.participants.map(\.name).joined(separator: " "),
                    advanceCase.participants.compactMap(\.debtAccount?.name).joined(separator: " "),
                    advanceCase.repayments.map(\.note).joined(separator: " "),
                    advanceCase.repayments.compactMap(\.receivedAccount?.name).joined(separator: " "),
                    advanceCase.tagIDs.compactMap { tagNameByID[$0] }.joined(separator: " "),
                    caseTransactions.compactMap(\.account?.name).joined(separator: " "),
                ]
                guard searchableValues.contains(where: {
                    $0.localizedCaseInsensitiveContains(searchText)
                }) else {
                    return nil
                }
            }

            return AdvanceCaseLedgerSummary(
                advanceCase: advanceCase,
                activityDate: activityDate,
                caseTransactions: caseTransactions
            )
        }
    }

    private static func ledgerItems(
        transactions: [FinancialTransaction],
        advanceCases: [AdvanceCaseLedgerSummary]
    ) -> [TransactionsListView.LedgerItem] {
        (transactions.map(TransactionsListView.LedgerItem.transaction)
            + advanceCases.map(TransactionsListView.LedgerItem.advanceCaseSummary))
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.id > rhs.id
                }
                return lhs.date > rhs.date
            }
    }

    private static func groupedTransactions(
        from ledgerItems: [TransactionsListView.LedgerItem],
        filterType: FilterType
    ) -> [TransactionsListView.TransactionGroup] {
        let formatter = DateFormatter()
        let grouping: (Date) -> String = { date in
            switch filterType {
            case .all: formatter.dateFormat = "yyyy年"; return formatter.string(from: date)
            case .year: formatter.dateFormat = "M月"; return formatter.string(from: date)
            case .month: formatter.dateFormat = "d日 (EEEE)"; return formatter.string(from: date)
            case .day, .custom: formatter.dateFormat = "M月d日 (EEEE)"; return formatter.string(from: date)
            }
        }
        let groupedDict = Dictionary(grouping: ledgerItems) { item in grouping(item.date) }
        let sortedKeys = groupedDict.keys.sorted { title1, title2 in
            guard let item1 = groupedDict[title1]?.first, let item2 = groupedDict[title2]?.first else { return title1 > title2 }
            return item1.date > item2.date
        }
        return sortedKeys.map { TransactionsListView.TransactionGroup(title: $0, items: groupedDict[$0] ?? []) }
    }

    private static func collapseTransferGroups(in items: [FinancialTransaction]) -> [FinancialTransaction] {
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

    private static func isAssetAdjustment(note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(TransactionSemantics.assetAdjustmentMarker)
    }
}

private struct LedgerSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "搜尋備註、分類、金額"
            )
        } else {
            content
        }
    }
}

struct AdvanceCaseLedgerSummary {
    struct CurrencyTotal: Identifiable {
        let currencyCode: String
        let amount: Decimal
        var id: String { currencyCode }
    }

    let advanceCase: AdvanceCase
    let activityDate: Date
    let paymentTotals: [CurrencyTotal]

    init(
        advanceCase: AdvanceCase,
        activityDate: Date,
        caseTransactions: [FinancialTransaction]
    ) {
        self.advanceCase = advanceCase
        self.activityDate = activityDate

        let initialGroupIDs = Set(advanceCase.participants.compactMap(\.initialTransferGroupID))
        let assetPayments = caseTransactions.filter {
            ($0.advanceEntryRole == .initialAsset
                || (
                    $0.advanceEntryRole == nil
                        && $0.transferGroupID.map(initialGroupIDs.contains) == true
                        && ($0.transferSide == .outgoing || $0.amount < 0)
                ))
                && $0.amount < 0
        }
        let grouped = Dictionary(grouping: assetPayments, by: \.currencyCode)
        self.paymentTotals = grouped.map { currencyCode, transactions in
            CurrencyTotal(
                currencyCode: currencyCode,
                amount: transactions.reduce(Decimal.zero) { $0 + abs($1.amount) }
            )
        }.sorted { $0.currencyCode < $1.currencyCode }
    }

    var outstandingAmount: Decimal {
        AdvanceService.outstandingAmount(for: advanceCase)
    }

    var isSettled: Bool {
        outstandingAmount <= Decimal(string: "0.0001")!
    }

    var directionLabel: String {
        advanceCase.direction == .othersAdvancedMe ? "他人代墊我" : "我代墊他人"
    }

    var paymentSummary: String {
        if paymentTotals.isEmpty {
            return advanceCase.direction == .othersAdvancedMe
                ? "\(AdvanceService.totalAdvanced(for: advanceCase).formatted(.currency(code: advanceCase.currencyCode)))（他人代付）"
                : AdvanceService.totalAdvanced(for: advanceCase)
                    .formatted(.currency(code: advanceCase.currencyCode))
        }
        return paymentTotals.map {
            $0.amount.formatted(.currency(code: $0.currencyCode))
        }.joined(separator: " + ")
    }
}

private struct AdvanceCaseSummaryRow: View {
    let summary: AdvanceCaseLedgerSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(summary.advanceCase.title)
                    Text(summary.directionLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("最近活動 \(summary.activityDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(summary.paymentSummary)
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(summary.isSettled ? .green : .secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(summary.isSettled ? 0.72 : 1)
    }

    private var summaryLine: String {
        let payer = summary.advanceCase.payerAccount?.name ?? "不影響自己帳戶"
        let ownShare = summary.advanceCase.myShareAmount.formatted(
            .currency(code: summary.advanceCase.currencyCode)
        )
        return "\(summary.advanceCase.participants.count) 人 · 自己份額 \(ownShare) · \(payer)"
    }

    private var statusText: String {
        if summary.isSettled {
            return "已結清"
        }
        let label = summary.advanceCase.direction == .othersAdvancedMe ? "待還" : "待收"
        return "\(label) \(summary.outstandingAmount.formatted(.currency(code: summary.advanceCase.currencyCode)))"
    }
}
