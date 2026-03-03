import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    
    @StateObject private var currencyService = CurrencyService.shared
    @AppStorage("mainCurrency") private var mainCurrency: String = "HKD"
    
    @State private var showingAddAccount = false
    @State private var accountToEdit: Account?
    @State private var editMode: EditMode = .inactive
    
    // 🔥 新增：控制是否顯示已歸檔帳戶
    @State private var showArchived = false
    
    // 篩選邏輯：根據 showArchived 決定顯示哪些
    var visibleAccounts: [Account] {
        allAccounts.filter { showArchived ? $0.isArchived : !$0.isArchived }
    }
    
    var assetAccounts: [Account] { visibleAccounts.filter { $0.type != .debt } }
    var debtAccounts: [Account] { visibleAccounts.filter { $0.type == .debt } }
    
    var body: some View {
        NavigationStack {
            List {
                // 統計區塊 (只在不顯示歸檔時顯示，避免混淆，或者您可以選擇都顯示)
                if !showArchived {
                    totalAssetsSection
                    currencyBreakdownSection
                } else {
                    Section {
                        Text("目前顯示已歸檔的帳戶")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .listRowBackground(Color.clear)
                }
                
                if !assetAccounts.isEmpty {
                    Section("一般帳戶") {
                        ForEach(assetAccounts) { account in
                            AccountRowLink(account: account, showArchived: showArchived) {
                                toggleArchive(account)
                            } deleteAction: {
                                deleteAccount(account)
                            } editAction: {
                                accountToEdit = account
                            }
                        }
                        .onMove { indices, newOffset in moveAccounts(in: assetAccounts, from: indices, to: newOffset) }
                    }
                }
                
                if !debtAccounts.isEmpty {
                    Section("借貸管理") {
                        ForEach(debtAccounts) { account in
                            AccountRowLink(account: account, showArchived: showArchived) {
                                toggleArchive(account)
                            } deleteAction: {
                                deleteAccount(account)
                            } editAction: {
                                accountToEdit = account
                            }
                        }
                        .onMove { indices, newOffset in moveAccounts(in: debtAccounts, from: indices, to: newOffset) }
                    }
                }
            }
            .navigationTitle(showArchived ? "已歸檔帳戶" : "帳戶")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode == .active ? "完成" : "排序") { withAnimation { editMode = (editMode == .active) ? .inactive : .active } }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        // 🔥 新增：歸檔切換選單
                        Menu {
                            Button(action: { showArchived.toggle() }) {
                                Label(showArchived ? "顯示活動帳戶" : "顯示已歸檔帳戶", systemImage: "archivebox")
                            }
                        } label: {
                            Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                        }
                        
                        Button(action: { showingAddAccount = true }) { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) { AddAccountView() }
            .sheet(item: $accountToEdit) { account in EditAccountView(account: account) }
            .task {
                await currencyService.fetchRates()
                normalizeSortOrdersIfNeeded()
            }
        }
    }
    
    // ... Subviews (totalAssetsSection, currencyBreakdownSection 保持不變) ...
    // 為了節省篇幅，這部分與之前相同，請保留
    
    private var totalAssetsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("總資產估算 (\(mainCurrency))").font(.subheadline).foregroundStyle(.secondary)
                Text(calculateTotalEstimatedAssets()).font(.system(size: 32, weight: .bold)).foregroundStyle(.primary)
                Text("根據即時匯率換算").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var currencyBreakdownSection: some View {
        Section("各幣種持有總額") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(currencyTotals, id: \.currency) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.currency).font(.caption).bold().foregroundStyle(.secondary)
                            Text(item.amount.formatted(.currency(code: item.currency))).font(.headline).fontWeight(.semibold).foregroundStyle(item.amount >= 0 ? Color.primary : Color.red)
                        }
                        .padding(12).background(Color(uiColor: .secondarySystemBackground)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }
    
    // MARK: - Logic Helpers
    
    private func toggleArchive(_ account: Account) {
        withAnimation {
            account.isArchived.toggle()
        }
    }
    
    private func deleteAccount(_ account: Account) {
        let transfers = account.transactions.filter { $0.type == .transfer }
        var handledGroupIDs = Set<UUID>()
        
        for tx in transfers {
            if let groupID = tx.transferGroupID {
                if handledGroupIDs.contains(groupID) {
                    continue
                }
                handledGroupIDs.insert(groupID)
                
                let descriptor = FetchDescriptor<FinancialTransaction>(
                    predicate: #Predicate { $0.transferGroupID == groupID }
                )
                if let groupedTransfers = try? modelContext.fetch(descriptor) {
                    for transfer in groupedTransfers {
                        modelContext.delete(transfer)
                    }
                }
                continue
            }
            
            if let linkedID = tx.linkedTransactionID {
                let descriptor = FetchDescriptor<FinancialTransaction>(predicate: #Predicate { $0.id == linkedID })
                if let linkedTx = try? modelContext.fetch(descriptor).first { modelContext.delete(linkedTx) }
            }
        }
        modelContext.delete(account)
    }
    
    private func moveAccounts(in subset: [Account], from source: IndexSet, to destination: Int) {
        guard let first = subset.first else { return }
        var revisedItems = subset
        revisedItems.move(fromOffsets: source, toOffset: destination)
        
        var activeAssets = sortedBucket(isArchived: false, isDebt: false)
        var activeDebts = sortedBucket(isArchived: false, isDebt: true)
        var archivedAssets = sortedBucket(isArchived: true, isDebt: false)
        var archivedDebts = sortedBucket(isArchived: true, isDebt: true)
        
        if first.isArchived {
            if first.type == .debt { archivedDebts = revisedItems }
            else { archivedAssets = revisedItems }
        } else {
            if first.type == .debt { activeDebts = revisedItems }
            else { activeAssets = revisedItems }
        }
        
        let combined = activeAssets + activeDebts + archivedAssets + archivedDebts
        for (index, item) in combined.enumerated() { item.sortOrder = index }
    }
    
    private func normalizeSortOrdersIfNeeded() {
        let combined = groupedAccounts()
        
        for (index, account) in combined.enumerated() {
            if account.sortOrder != index {
                for (newIndex, item) in combined.enumerated() { item.sortOrder = newIndex }
                return
            }
        }
    }
    
    private func groupedAccounts() -> [Account] {
        let activeAssets = sortedBucket(isArchived: false, isDebt: false)
        let activeDebts = sortedBucket(isArchived: false, isDebt: true)
        let archivedAssets = sortedBucket(isArchived: true, isDebt: false)
        let archivedDebts = sortedBucket(isArchived: true, isDebt: true)
        return activeAssets + activeDebts + archivedAssets + archivedDebts
    }
    
    private func sortedBucket(isArchived: Bool, isDebt: Bool) -> [Account] {
        allAccounts
            .filter { $0.isArchived == isArchived && (($0.type == .debt) == isDebt) }
            .sorted(by: accountOrder)
    }
    
    private func accountOrder(_ lhs: Account, _ rhs: Account) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }
    
    private func calculateTotalEstimatedAssets() -> String {
        // 只計算未歸檔的資產
        var total: Decimal = 0
        let activeAccounts = allAccounts.filter { !$0.isArchived }
        
        for account in activeAccounts {
            total += currencyService.convert(amount: account.baseBalance, from: account.currency)
            for tx in account.transactions {
                total += currencyService.convert(amount: tx.amount, from: tx.currencyCode)
            }
        }
        return total.formatted(.currency(code: mainCurrency))
    }
    
    struct CurrencyTotal { let currency: String; let amount: Decimal }
    var currencyTotals: [CurrencyTotal] {
        var totals: [String: Decimal] = [:]
        let activeAccounts = allAccounts.filter { !$0.isArchived }
        
        for account in activeAccounts {
            if account.baseBalance != 0 { totals[account.currency, default: 0] += account.baseBalance }
            for tx in account.transactions { totals[tx.currencyCode, default: 0] += tx.amount }
        }
        return totals.map { CurrencyTotal(currency: $0.key, amount: $0.value) }.sorted { $0.currency < $1.currency }
    }
}

// MARK: - Row Components (支援歸檔操作)

struct AccountRowLink: View {
    let account: Account
    let showArchived: Bool
    let archiveAction: () -> Void
    let deleteAction: () -> Void
    let editAction: () -> Void
    
    var body: some View {
        NavigationLink(destination: AccountDetailView(account: account)) { AccountRow(account: account) }
            .swipeActions(edge: .leading) {
                // 🔥 左滑：歸檔/還原
                Button(action: archiveAction) {
                    Label(showArchived ? "還原" : "歸檔", systemImage: showArchived ? "tray.and.arrow.up" : "archivebox")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: deleteAction) { Label("刪除", systemImage: "trash") }
                Button(action: editAction) { Label("編輯", systemImage: "pencil") }.tint(.blue)
            }
    }
}

struct AccountRow: View {
    let account: Account
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(account.name).font(.headline).strikethrough(account.isArchived) // 歸檔加刪除線
                HStack(spacing: 4) {
                    if account.type == .debt { Image(systemName: "person.2.fill").font(.caption2) }
                    Text(account.type.displayName)
                    if account.type != .debt { Text("•"); Text(account.currency) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                let balances = calculateBalances(account: account)
                if balances.isEmpty { Text("0.00").foregroundStyle(.secondary) }
                else if balances.count == 1, let first = balances.first {
                    Text(first.value.formatted(.currency(code: first.key))).bold().foregroundStyle(first.value >= 0 ? Color.primary : Color.red)
                } else {
                    ForEach(balances.prefix(2), id: \.key) { curr, amount in
                        Text(amount.formatted(.currency(code: curr))).font(.subheadline).foregroundStyle(amount >= 0 ? Color.primary : Color.red)
                    }
                    if balances.count > 2 { Text("...").font(.caption) }
                }
            }
        }
        .opacity(account.isArchived ? 0.6 : 1.0) // 歸檔變淡
    }
    
    func calculateBalances(account: Account) -> [(key: String, value: Decimal)] {
        var dict: [String: Decimal] = [:]
        if account.baseBalance != 0 { dict[account.currency] = account.baseBalance }
        for tx in account.transactions { dict[tx.currencyCode, default: 0] += tx.amount }
        return dict.filter { $0.value != 0 }.sorted { $0.key < $1.key }
    }
}
