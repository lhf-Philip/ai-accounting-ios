import SwiftUI
import SwiftData

struct AdvancesView: View {
    @Query(sort: \AdvanceCase.date, order: .reverse) private var advanceCases: [AdvanceCase]
    @StateObject private var currencyService = CurrencyService.shared
    @State private var showingAddAdvanceCase = false
    @State private var viewMode: ViewMode = .byCase
    
    enum ViewMode: String, CaseIterable {
        case byCase = "按代墊單"
        case byParticipant = "按對象"
    }
    
    struct ParticipantAggregate: Identifiable {
        let id: String
        let name: String
        let caseCount: Int
        let totalOwedMain: Decimal
        let totalRepaidMain: Decimal
        let totalRemainingMain: Decimal
    }
    
    private var activeCases: [AdvanceCase] {
        advanceCases.filter { AdvanceService.outstandingAmount(for: $0) > 0 }
    }
    
    private var settledCases: [AdvanceCase] {
        advanceCases.filter { AdvanceService.outstandingAmount(for: $0) == 0 }
    }
    
    private var participantAggregates: [ParticipantAggregate] {
        var owedTotals: [String: Decimal] = [:]
        var repaidTotals: [String: Decimal] = [:]
        var remainingTotals: [String: Decimal] = [:]
        var names: [String: String] = [:]
        var caseSets: [String: Set<UUID>] = [:]
        
        for advanceCase in advanceCases {
            for participant in advanceCase.participants {
                let key = participant.debtAccount?.id.uuidString ?? "name::\(participant.name.lowercased())"
                let name = participant.debtAccount?.name ?? participant.name
                
                names[key] = name
                caseSets[key, default: []].insert(advanceCase.id)
                
                let owed = currencyService.convert(amount: participant.owedAmount, from: advanceCase.currencyCode)
                let repaid = currencyService.convert(amount: participant.repaidAmount, from: advanceCase.currencyCode)
                let remaining = currencyService.convert(amount: participant.remainingAmount, from: advanceCase.currencyCode)
                
                owedTotals[key, default: 0] += owed
                repaidTotals[key, default: 0] += repaid
                remainingTotals[key, default: 0] += remaining
            }
        }
        
        return names.keys.map { key in
            ParticipantAggregate(
                id: key,
                name: names[key] ?? "未命名",
                caseCount: caseSets[key]?.count ?? 0,
                totalOwedMain: owedTotals[key, default: 0],
                totalRepaidMain: repaidTotals[key, default: 0],
                totalRemainingMain: remainingTotals[key, default: 0]
            )
        }
        .sorted {
            if $0.totalRemainingMain == $1.totalRemainingMain {
                return $0.name < $1.name
            }
            return $0.totalRemainingMain > $1.totalRemainingMain
        }
    }
    
    var body: some View {
        List {
            Section("檢視方式") {
                Picker("檢視方式", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            if advanceCases.isEmpty {
                Section {
                    ContentUnavailableView(
                        "尚無代墊紀錄",
                        systemImage: "person.2.fill",
                        description: Text("可用右上角加號新增代墊，並追蹤每位對象還款進度。")
                    )
                }
            } else {
                if viewMode == .byCase {
                    if !activeCases.isEmpty {
                        Section("待收款") {
                            ForEach(activeCases) { advanceCase in
                                NavigationLink(destination: AdvanceCaseDetailView(advanceCase: advanceCase)) {
                                    advanceCaseRow(advanceCase)
                                }
                            }
                        }
                    }
                    
                    if !settledCases.isEmpty {
                        Section("已結清") {
                            ForEach(settledCases) { advanceCase in
                                NavigationLink(destination: AdvanceCaseDetailView(advanceCase: advanceCase)) {
                                    advanceCaseRow(advanceCase)
                                }
                            }
                        }
                    }
                } else {
                    if participantAggregates.isEmpty {
                        Section {
                            ContentUnavailableView(
                                "尚無對象彙總",
                                systemImage: "person.2.slash",
                                description: Text("目前沒有可統計的代墊對象。")
                            )
                        }
                    } else {
                        Section("對象總覽 (\(currencyService.mainCurrency))") {
                            ForEach(participantAggregates) { item in
                                participantAggregateRow(item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("代墊追蹤")
        .task {
            await currencyService.fetchRates()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddAdvanceCase = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAdvanceCase) {
            AddAdvanceCaseView()
        }
    }
    
    @ViewBuilder
    private func advanceCaseRow(_ advanceCase: AdvanceCase) -> some View {
        let receivable = advanceCase.participants.reduce(Decimal.zero) { $0 + $1.owedAmount }
        let repaid = advanceCase.participants.reduce(Decimal.zero) { $0 + $1.repaidAmount }
        let outstanding = AdvanceService.outstandingAmount(for: advanceCase)
        let progress: Double = receivable > 0
            ? min(max((NSDecimalNumber(decimal: repaid).doubleValue / NSDecimalNumber(decimal: receivable).doubleValue), 0), 1)
            : 1
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(advanceCase.title)
                    .font(.headline)
                Spacer()
                Text(outstanding.formatted(.currency(code: advanceCase.currencyCode)))
                    .font(.subheadline)
                    .foregroundStyle(outstanding == 0 ? .green : .red)
            }
            
            ProgressView(value: progress, total: 1.0)
                .tint(outstanding == 0 ? .green : .orange)
            
            HStack {
                Text("已還 \(repaid.formatted(.currency(code: advanceCase.currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(advanceCase.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func participantAggregateRow(_ item: ParticipantAggregate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name)
                    .font(.headline)
                Spacer()
                Text(item.totalRemainingMain.formatted(.currency(code: currencyService.mainCurrency)))
                    .foregroundStyle(item.totalRemainingMain == 0 ? .green : .red)
            }
            
            HStack {
                Text("欠款 \(item.totalOwedMain.formatted(.currency(code: currencyService.mainCurrency)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已還 \(item.totalRepaidMain.formatted(.currency(code: currencyService.mainCurrency)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("關聯代墊單：\(item.caseCount) 筆")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct AdvanceCaseDetailView: View {
    private enum DeleteMode {
        case trackingOnly
        case trackingAndLinkedTransactions
        
        var deleteLinkedTransactions: Bool {
            self == .trackingAndLinkedTransactions
        }
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FinancialTransaction.date, order: .reverse)
    private var transactions: [FinancialTransaction]
    
    let advanceCase: AdvanceCase
    @State private var selectedParticipantForRepayment: AdvanceParticipant?
    @State private var selectedParticipantForEdit: AdvanceParticipant?
    @State private var selectedRepaymentForEdit: AdvanceRepayment?
    @State private var showingCaseEditor = false
    @State private var repaymentToRollback: AdvanceRepayment?
    @State private var selectedDeleteMode: DeleteMode?
    @State private var showingDeleteModeDialog = false
    @State private var showingDeleteConfirm = false
    @State private var showingRollbackAlert = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var settlementDirection: AdvanceService.SettlementDirection = .iAdvancedOthers
    
    private var sortedParticipants: [AdvanceParticipant] {
        advanceCase.participants.sorted {
            if $0.remainingAmount == $1.remainingAmount {
                return $0.name < $1.name
            }
            return $0.remainingAmount > $1.remainingAmount
        }
    }
    
    private var sortedRepayments: [AdvanceRepayment] {
        advanceCase.repayments.sorted { $0.date > $1.date }
    }

    private var linkedAssetTransactionCount: Int {
        linkedTransactions.filter { $0.account?.type != .debt }.count
    }

    private var linkedDebtTransactionCount: Int {
        linkedTransactions.filter { $0.account?.type == .debt }.count
    }

    private var linkedTransactions: [FinancialTransaction] {
        let participantIDs = Set(advanceCase.participants.map(\.id))
        let groupIDs = Set(
            advanceCase.participants.compactMap(\.initialTransferGroupID)
                + advanceCase.repayments.compactMap(\.linkedTransferGroupID)
        )
        return transactions.filter { transaction in
            transaction.advanceCaseID == advanceCase.id
                || transaction.advanceParticipantID.map(participantIDs.contains) == true
                || transaction.transferGroupID.map(groupIDs.contains) == true
                || transaction.id == advanceCase.selfExpenseTransactionID
        }
    }

    private var initialPaymentTransactions: [FinancialTransaction] {
        linkedTransactions
            .filter { transaction in
                transaction.advanceEntryRole == .initialAsset
                    || (
                        transaction.advanceEntryRole == nil
                            && transaction.type == .transfer
                            && (transaction.transferSide == .outgoing || transaction.amount < 0)
                            && advanceCase.participants.contains { participant in
                                participant.initialTransferGroupID == transaction.transferGroupID
                            }
                    )
            }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        List {
            Section("摘要") {
                summaryRow(
                    title: "代墊總額",
                    value: AdvanceService.totalAdvanced(for: advanceCase).formatted(.currency(code: advanceCase.currencyCode))
                )
                summaryRow(
                    title: "自己的支出",
                    value: advanceCase.myShareAmount.formatted(.currency(code: advanceCase.currencyCode))
                )
                summaryRow(
                    title: settlementDirection == .iAdvancedOthers ? "待收總額" : "待還總額",
                    value: AdvanceService.outstandingAmount(for: advanceCase).formatted(.currency(code: advanceCase.currencyCode))
                )
                summaryRow(
                    title: settlementDirection == .iAdvancedOthers ? "付款帳戶" : "付款來源",
                    value: settlementDirection == .iAdvancedOthers ? (advanceCase.payerAccount?.name ?? "未指定") : "他人代付（不影響自己帳戶）"
                )
                summaryRow(
                    title: "帳務儲存",
                    value: settlementDirection == .iAdvancedOthers ? "借貸帳戶轉帳" : "借貸帳戶支出"
                )
            }

            Section("實際付款") {
                if initialPaymentTransactions.isEmpty {
                    Text(settlementDirection == .othersAdvancedMe
                         ? "由他人代付，自己的資產帳戶沒有變動。"
                         : "找不到可唯一識別的實際付款分錄，請執行資料健康檢查。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(initialPaymentTransactions) { transaction in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(transaction.account?.name ?? "未指定帳戶")
                                if let participant = advanceCase.participants.first(where: {
                                    $0.id == transaction.advanceParticipantID
                                }) {
                                    Text(participant.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(abs(transaction.amount).formatted(.currency(code: transaction.currencyCode)))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            Section("帳務影響") {
                summaryRow(
                    title: "收入／支出報表",
                    value: settlementDirection == .iAdvancedOthers
                        ? (advanceCase.myShareAmount > 0 ? "只計自己的份額" : "不計入")
                        : "代付當日計為支出"
                )
                summaryRow(title: "資產帳戶", value: "\(linkedAssetTransactionCount) 筆流水")
                summaryRow(title: "借貸帳戶", value: "\(linkedDebtTransactionCount) 筆流水")
            }
            
            Section {
                Button(role: .destructive) {
                    showingDeleteModeDialog = true
                } label: {
                    Label("刪除此代墊單", systemImage: "trash")
                }
            }
            
            Section(settlementDirection == .iAdvancedOthers ? "對象還款狀態" : "對象欠款狀態") {
                ForEach(sortedParticipants) { participant in
                    participantRow(participant)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                selectedParticipantForEdit = participant
                            } label: {
                                Label("更正欠款", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
            }
            
            if sortedRepayments.isEmpty {
                Section("還款紀錄") {
                    Text("尚未記錄還款")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("還款紀錄") {
                    ForEach(sortedRepayments) { repayment in
                        repaymentRow(repayment)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if AdvanceService.repaymentRecordKind(note: repayment.note) == .ordinary,
                                   repayment.linkedTransferGroupID != nil {
                                    selectedRepaymentForEdit = repayment
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if AdvanceService.repaymentRecordKind(note: repayment.note) == .ordinary,
                                   repayment.linkedTransferGroupID != nil {
                                    Button {
                                        selectedRepaymentForEdit = repayment
                                    } label: {
                                        Label("編輯", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                Button(role: .destructive) {
                                    repaymentToRollback = repayment
                                    showingRollbackAlert = true
                                } label: {
                                    Label("撤銷", systemImage: "arrow.uturn.backward.circle")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(advanceCase.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編輯") {
                    showingCaseEditor = true
                }
            }
        }
        .sheet(isPresented: $showingCaseEditor) {
            AdvanceStructuralEditorView(advanceCase: advanceCase)
        }
        .sheet(item: $selectedParticipantForRepayment) { participant in
            AddAdvanceRepaymentView(advanceCase: advanceCase, participant: participant)
        }
        .sheet(item: $selectedParticipantForEdit) { participant in
            EditAdvanceParticipantView(advanceCase: advanceCase, participant: participant)
        }
        .sheet(item: $selectedRepaymentForEdit) { repayment in
            EditAdvanceTransferView(repayment: repayment)
        }
        .confirmationDialog("刪除代墊單", isPresented: $showingDeleteModeDialog, titleVisibility: .visible) {
            Button("只刪追蹤記錄", role: .destructive) {
                selectedDeleteMode = .trackingOnly
                showingDeleteConfirm = true
            }
            Button("刪除追蹤與相關交易", role: .destructive) {
                selectedDeleteMode = .trackingAndLinkedTransactions
                showingDeleteConfirm = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("可選擇只刪代墊追蹤，或同時刪除建立此代墊時產生的借貸轉帳與自己份額支出。")
        }
        .alert("確認刪除此代墊單？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {
                selectedDeleteMode = nil
            }
            Button("確認刪除", role: .destructive) {
                deleteAdvanceCase()
            }
        } message: {
            if case .trackingAndLinkedTransactions = selectedDeleteMode {
                Text("將刪除代墊追蹤資料，並嘗試刪除關聯借貸轉帳與自己份額支出。此操作無法復原。")
            } else {
                Text("將只刪除代墊追蹤資料，原本的實際交易紀錄會保留。此操作無法復原。")
            }
        }
        .alert("確認撤銷紀錄？", isPresented: $showingRollbackAlert, presenting: repaymentToRollback) { repayment in
            Button("取消", role: .cancel) {}
            Button("撤銷", role: .destructive) {
                rollbackRepayment(repayment)
            }
        } message: { repayment in
            Text(rollbackMessage(for: repayment))
        }
        .alert("操作失敗", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task(id: advanceCase.updatedAt) {
            if let participant = advanceCase.participants.first {
                settlementDirection = AdvanceService.inferSettlementDirection(
                    for: participant,
                    modelContext: modelContext
                )
            } else {
                settlementDirection = .iAdvancedOthers
            }
        }
    }
    
    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func participantRow(_ participant: AdvanceParticipant) -> some View {
        let owed = participant.owedAmount
        let repaid = participant.repaidAmount
        let remaining = participant.remainingAmount
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(participant.name)
                    .font(.headline)
                Spacer()
                Text(remaining.formatted(.currency(code: advanceCase.currencyCode)))
                    .foregroundStyle(remaining == 0 ? .green : .red)
            }
            
            HStack {
                Text((settlementDirection == .iAdvancedOthers ? "應還 " : "應付 ") + owed.formatted(.currency(code: advanceCase.currencyCode)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text((settlementDirection == .iAdvancedOthers ? "已還 " : "已付 ") + repaid.formatted(.currency(code: advanceCase.currencyCode)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if remaining > 0 {
                HStack(spacing: 8) {
                    Button {
                        selectedParticipantForRepayment = participant
                    } label: {
                        Label(settlementDirection == .iAdvancedOthers ? "記錄還款" : "記錄付款", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    
                    Button {
                        selectedParticipantForEdit = participant
                    } label: {
                        Label("更正欠款", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            } else {
                Button {
                    selectedParticipantForEdit = participant
                } label: {
                    Label("更正欠款", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func repaymentRow(_ repayment: AdvanceRepayment) -> some View {
        let recordKind = AdvanceService.repaymentRecordKind(note: repayment.note)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repayment.participant?.name ?? "未指定對象")
                        .font(.body)
                        .fontWeight(.semibold)
                    if recordKind != .ordinary {
                        Text(repaymentKindLabel(recordKind))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Text(repayment.amount.formatted(.currency(code: repayment.currencyCode)))
                    .font(.subheadline)
                    .foregroundStyle(recordKind == .ordinary ? .green : .orange)
            }
            
            HStack(spacing: 6) {
                Text(repayment.date.formatted(date: .abbreviated, time: .shortened))
                if recordKind == .ordinary {
                    Text("•")
                    Text("入帳：\(repayment.receivedAccount?.name ?? "未指定")")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if repayment.currencyCode != advanceCase.currencyCode {
                Text("折算 \(repayment.normalizedAmount.formatted(.currency(code: advanceCase.currencyCode)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if !repayment.note.isEmpty {
                Text(repayment.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func rollbackRepayment(_ repayment: AdvanceRepayment) {
        do {
            switch AdvanceService.repaymentRecordKind(note: repayment.note) {
            case .ordinary:
                try AdvanceService.rollbackRepayment(
                    advanceCase: advanceCase,
                    repayment: repayment,
                    modelContext: modelContext
                )
            case .mutualDebtOffset(let offsetID):
                _ = try AdvanceService.rollbackMutualDebtOffset(
                    offsetGroupID: offsetID,
                    modelContext: modelContext
                )
            case .manualDebtSettlement(let settlementID):
                _ = try AdvanceService.rollbackManualDebtSettlement(
                    settlementID: settlementID,
                    modelContext: modelContext
                )
            case .invalidSpecial:
                throw AdvanceServiceError.specialRepaymentRequiresGroupRollback
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func repaymentKindLabel(_ kind: AdvanceService.RepaymentRecordKind) -> String {
        switch kind {
        case .ordinary:
            return "還款"
        case .mutualDebtOffset:
            return "債務抵銷"
        case .manualDebtSettlement:
            return "跨幣種平賬"
        case .invalidSpecial:
            return "特殊結算（資料異常）"
        }
    }

    private func rollbackMessage(for repayment: AdvanceRepayment) -> String {
        switch AdvanceService.repaymentRecordKind(note: repayment.note) {
        case .ordinary:
            return "將刪除 \(repayment.amount.formatted(.currency(code: repayment.currencyCode))) 的還款紀錄，並同步刪除對應借貸轉帳。"
        case .mutualDebtOffset:
            return "將整組撤銷這次債務抵銷，所有受影響案件的未清金額都會回復。"
        case .manualDebtSettlement:
            return "將整組撤銷這次跨幣種平賬，所有受影響案件的未清金額都會回復。"
        case .invalidSpecial:
            return "這筆特殊結算的識別資料不完整，請先使用資料健康檢查修復。"
        }
    }
    
    private func deleteAdvanceCase() {
        guard let mode = selectedDeleteMode else { return }
        
        do {
            _ = try AdvanceService.deleteAdvanceCase(
                advanceCase,
                deleteLinkedTransactions: mode.deleteLinkedTransactions,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

struct EditAdvanceCaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]

    let advanceCase: AdvanceCase

    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []
    @State private var direction: AdvanceService.SettlementDirection = .iAdvancedOthers
    @State private var showingError = false
    @State private var errorMessage = ""

    private var availableCategories: [Category] {
        direction == .othersAdvancedMe
            ? categories.filter { $0.kind.supports(.expense) }
            : []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("案件") {
                    TextField("案件名稱", text: $title)
                    DatePicker("日期", selection: $date)
                    LabeledContent("方向", value: direction == .iAdvancedOthers ? "我代墊他人" : "他人代墊我")
                    LabeledContent("案件幣種", value: advanceCase.currencyCode)
                    Text("方向與案件幣種會改變所有底層分錄；請先逐筆確認參與人及還款，再使用重建流程。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if direction == .othersAdvancedMe {
                    Section("支出分類") {
                        Picker("分類", selection: $selectedCategory) {
                            Text("無分類").tag(nil as Category?)
                            ForEach(availableCategories) { category in
                                Text(category.name).tag(category as Category?)
                            }
                        }
                    }
                }

                Section("標籤") {
                    ForEach(tags) { tag in
                        Toggle(tag.name, isOn: Binding(
                            get: { selectedTags.contains(tag) },
                            set: { selected in
                                if selected {
                                    selectedTags.insert(tag)
                                } else {
                                    selectedTags.remove(tag)
                                }
                            }
                        ))
                    }
                }

                Section("備註") {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }

                Section("完整金額編輯") {
                    Text("返回案件詳情後，可逐位修改債務帳戶、欠款、實際付款帳戶、金額與幣種；每筆普通還款亦可獨立修改。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("編輯代墊案件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
            .alert("無法儲存", isPresented: $showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                title = advanceCase.title
                date = advanceCase.date
                note = advanceCase.note
                selectedCategory = advanceCase.expenseCategory
                selectedTags = Set(tags.filter { advanceCase.tagIDs.contains($0.id) })
                if let participant = advanceCase.participants.first {
                    direction = AdvanceService.inferSettlementDirection(
                        for: participant,
                        modelContext: modelContext
                    )
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            showError("請輸入案件名稱。")
            return
        }
        guard let participant = advanceCase.participants.first else {
            showError("案件沒有可編輯的參與人。")
            return
        }

        let payment = initialPayment(for: participant)
        do {
            try AdvanceService.updateInitialEntry(
                advanceCase: advanceCase,
                participant: participant,
                draft: .init(
                    caseTitle: trimmedTitle,
                    participantName: participant.name,
                    debtAccount: participant.debtAccount,
                    payerAccount: direction == .iAdvancedOthers
                        ? (payment?.account ?? advanceCase.payerAccount)
                        : nil,
                    owedAmount: participant.owedAmount,
                    paymentAmount: payment.map { abs($0.amount) },
                    paymentCurrencyCode: payment?.currencyCode,
                    date: date,
                    note: note,
                    category: direction == .othersAdvancedMe ? selectedCategory : nil,
                    tags: Array(selectedTags)
                ),
                modelContext: modelContext
            )
            dismiss()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func initialPayment(for participant: AdvanceParticipant) -> FinancialTransaction? {
        guard let groupID = participant.initialTransferGroupID else { return nil }
        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        return try? modelContext.fetch(descriptor).first(where: {
            $0.advanceEntryRole == .initialAsset
                || $0.transferSide == .outgoing
                || $0.amount < 0
        })
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

struct AddAdvanceCaseView: View {
    private enum AdvanceDirection: String, CaseIterable, Identifiable {
        case iAdvancedOthers = "我代墊他人"
        case othersAdvancedMe = "他人代墊我"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    fileprivate struct ParticipantDraft: Identifiable {
        let id = UUID()
        var debtAccount: Account?
        var amountString: String = ""
    }
    
    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var direction: AdvanceDirection = .iAdvancedOthers
    @State private var myShareString = ""
    @State private var selectedCurrency = "HKD"
    @State private var selectedPayerAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []
    @State private var participantDrafts: [ParticipantDraft] = [ParticipantDraft()]
    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var showingAddDebtAccount = false
    @State private var newDebtAccountName = ""
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    private var myAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.type != .debt }
    }
    
    private var debtAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.type == .debt }
    }
    
    private var flowCategories: [Category] {
        categories.filter { $0.kind.supports(.expense) }
    }

    private var requiresPayerAccount: Bool {
        direction == .iAdvancedOthers
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    Picker("方向", selection: $direction) {
                        ForEach(AdvanceDirection.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("代墊名稱 (例如：聚餐 2026-03-01)", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    if requiresPayerAccount {
                        Picker("付款帳戶", selection: $selectedPayerAccount) {
                            Text("選擇帳戶").tag(nil as Account?)
                            ForEach(myAccounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                        .onChange(of: selectedPayerAccount) { _, _ in
                            if let account = selectedPayerAccount {
                                selectedCurrency = account.currency
                            }
                        }
                    } else {
                        Text("他人代你付款時，你自己的帳戶沒有變動；建立時只會記錄支出與你欠對方的債務。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !requiresPayerAccount {
                        HStack {
                            Text("幣種")
                            Spacer()
                            Picker("幣種", selection: $selectedCurrency) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                        }
                    } else {
                        HStack {
                            Text("幣種")
                            Spacer()
                            Picker("幣種", selection: $selectedCurrency) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                        }
                    }
                }
                
                if direction == .iAdvancedOthers {
                    Section("自己的份額") {
                        TextField("0 (可留空)", text: Binding(
                            get: { myShareString },
                            set: { myShareString = sanitizePositiveDecimalInput($0) }
                        ))
                        .keyboardType(.decimalPad)
                        
                        Picker("支出分類", selection: $selectedCategory) {
                            Text("不設定").tag(nil as Category?)
                            ForEach(flowCategories) { category in
                                Text(category.name).tag(category as Category?)
                            }
                        }
                        
                        tagSelectionView
                    }
                } else {
                    Section("支出分類與標籤") {
                        Picker("支出分類", selection: $selectedCategory) {
                            Text("不設定").tag(nil as Category?)
                            ForEach(flowCategories) { category in
                                Text(category.name).tag(category as Category?)
                            }
                        }
                        
                        tagSelectionView
                    }
                }
                
                Section(direction == .iAdvancedOthers ? "代墊對象" : "我欠的人") {
                    if debtAccounts.isEmpty {
                        Text("尚未建立借貸/債務帳戶，可在此直接新增。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        ForEach(participantDrafts) { draft in
                            AdvanceParticipantDraftRow(
                                draft: binding(for: draft),
                                debtAccounts: debtAccounts,
                                amountPlaceholder: direction == .iAdvancedOthers ? "代墊金額" : "我欠此人的金額",
                                canRemove: participantDrafts.count > 1,
                                onRemove: {
                                    participantDrafts.removeAll { $0.id == draft.id }
                                },
                                sanitizeAmount: sanitizePositiveDecimalInput
                            )
                        }
                        
                        Button {
                            participantDrafts.append(ParticipantDraft())
                        } label: {
                            Label("新增對象", systemImage: "plus.circle")
                        }
                    }
                    
                    Button {
                        showingAddDebtAccount = true
                    } label: {
                        Label("新增債務人物", systemImage: "person.badge.plus")
                    }
                }
                
                Section("備註") {
                    TextField("可填入店名、說明等", text: $note)
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("新增代墊")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        hideKeyboard()
                    }
                }
            }
            .alert("新增標籤", isPresented: $showingAddTag) {
                TextField("標籤名稱", text: $newTagName)
                Button("取消", role: .cancel) { newTagName = "" }
                Button("新增") { createTag() }
            }
            .alert("新增債務人物", isPresented: $showingAddDebtAccount) {
                TextField("人物名稱", text: $newDebtAccountName)
                Button("取消", role: .cancel) {
                    newDebtAccountName = ""
                }
                Button("新增") { createDebtAccount() }
            } message: {
                Text("會建立一個「借貸/債務」帳戶並自動選擇。")
            }
            .alert("無法儲存", isPresented: $showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if selectedPayerAccount == nil, let first = myAccounts.first {
                    selectedPayerAccount = first
                    selectedCurrency = first.currency
                }
            }
            .onChange(of: direction) { _, newDirection in
                if let selectedCategory, !flowCategories.contains(where: { $0.id == selectedCategory.id }) {
                    self.selectedCategory = nil
                }
                if newDirection == .othersAdvancedMe {
                    myShareString = ""
                    selectedPayerAccount = nil
                } else if selectedPayerAccount == nil, let first = myAccounts.first {
                    selectedPayerAccount = first
                    selectedCurrency = first.currency
                }
            }
        }
    }

    private var canSave: Bool {
        !requiresPayerAccount || selectedPayerAccount != nil
    }

    private var tagSelectionView: some View {
        Group {
            HStack {
                Text("標籤")
                Spacer()
                Button(action: { showingAddTag = true }) {
                    Label("新增", systemImage: "plus")
                        .font(.caption)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(tags) { tag in
                        let isSelected = selectedTags.contains(tag)
                        Text(tag.name)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .cornerRadius(16)
                            .onTapGesture {
                                if isSelected {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                    }
                }
            }
        }
    }
    
    private func save() {
        if requiresPayerAccount, selectedPayerAccount == nil {
            showError("請選擇付款帳戶。")
            return
        }
        
        let myShare: Decimal
        if myShareString.isEmpty {
            myShare = 0
        } else if let parsed = Decimal(string: myShareString), parsed >= 0 {
            myShare = parsed
        } else {
            showError("自己的份額格式不正確。")
            return
        }
        
        var participantInputs: [AdvanceService.ParticipantInput] = []
        for draft in participantDrafts {
            guard let debtAccount = draft.debtAccount else {
                showError("請為每位對象選擇借貸帳戶。")
                return
            }
            guard let amount = Decimal(string: draft.amountString), amount > 0 else {
                showError("請填寫每位對象大於 0 的代墊金額。")
                return
            }
            participantInputs.append(.init(debtAccount: debtAccount, owedAmount: amount))
        }
        
        guard !participantInputs.isEmpty else {
            showError("請至少新增一位代墊對象。")
            return
        }
        
        do {
            _ = try AdvanceService.createAdvanceCase(
                title: title,
                date: date,
                currencyCode: selectedCurrency,
                myShareAmount: direction == .othersAdvancedMe ? 0 : myShare,
                note: note,
                payerAccount: selectedPayerAccount,
                category: selectedCategory,
                tags: Array(selectedTags),
                participants: participantInputs,
                isBorrowedByMe: direction == .othersAdvancedMe,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            modelContext.rollback()
            showError(error.localizedDescription)
        }
    }

    private func createTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tag = Tag(name: trimmed)
        modelContext.insert(tag)
        selectedTags.insert(tag)
        newTagName = ""
    }

    private func createDebtAccount() {
        let trimmed = newDebtAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = debtAccounts.first(where: { $0.name == trimmed }) {
            autoSelectDebtAccount(existing)
            newDebtAccountName = ""
            return
        }

        let nextSortOrder = (allAccounts.map(\.sortOrder).max() ?? -1) + 1
        let account = Account(
            name: trimmed,
            currency: selectedCurrency,
            type: .debt,
            baseBalance: 0,
            sortOrder: nextSortOrder
        )
        modelContext.insert(account)
        do {
            try modelContext.save()
        } catch {
            showError("建立債務人物失敗：\(error.localizedDescription)")
            return
        }
        autoSelectDebtAccount(account)
        newDebtAccountName = ""
    }

    private func autoSelectDebtAccount(_ account: Account) {
        if let index = participantDrafts.firstIndex(where: { $0.debtAccount == nil }) {
            participantDrafts[index].debtAccount = account
            return
        }
        participantDrafts.append(ParticipantDraft(debtAccount: account))
    }

    private func binding(for draft: ParticipantDraft) -> Binding<ParticipantDraft> {
        Binding(
            get: {
                participantDrafts.first(where: { $0.id == draft.id }) ?? draft
            },
            set: { updatedDraft in
                guard let index = participantDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
                participantDrafts[index] = updatedDraft
            }
        )
    }
    
    private func sanitizePositiveDecimalInput(_ value: String) -> String {
        let allowed = value.filter { "0123456789.".contains($0) }
        var result = ""
        var hasDot = false
        
        for char in allowed {
            if char == "." {
                if hasDot { continue }
                hasDot = true
            }
            result.append(char)
        }
        
        return result == "." ? "" : result
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

private struct AdvanceParticipantDraftRow: View {
    @Binding var draft: AddAdvanceCaseView.ParticipantDraft
    let debtAccounts: [Account]
    let amountPlaceholder: String
    let canRemove: Bool
    let onRemove: () -> Void
    let sanitizeAmount: (String) -> String

    var body: some View {
        VStack(spacing: 10) {
            Picker("對象", selection: $draft.debtAccount) {
                Text("選擇對象").tag(nil as Account?)
                ForEach(debtAccounts) { account in
                    Text(account.name).tag(account as Account?)
                }
            }

            TextField(amountPlaceholder, text: Binding(
                get: { draft.amountString },
                set: { draft.amountString = sanitizeAmount($0) }
            ))
            .keyboardType(.decimalPad)

            if canRemove {
                Button(role: .destructive, action: onRemove) {
                    Text("移除此對象")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddAdvanceRepaymentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @StateObject private var currencyService = CurrencyService.shared
    
    let advanceCase: AdvanceCase
    let participant: AdvanceParticipant
    
    private enum EntryMode: String, CaseIterable, Identifiable {
        case normal
        case split
        case merge
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .normal: return "一般"
            case .split: return "分拆 (1 -> 多)"
            case .merge: return "合併 (多 -> 1)"
            }
        }
    }
    
    private struct SplitLeg: Identifiable {
        let id = UUID()
        var receiveAccount: Account?
        var currency: String = "HKD"
        var amountString: String = ""
    }
    
    private struct MergeLeg: Identifiable {
        let id = UUID()
        var currency: String = "HKD"
        var amountString: String = ""
    }
    
    @State private var entryMode: EntryMode = .normal
    @State private var selectedReceiveAccount: Account?
    @State private var amountString = ""
    @State private var selectedCurrency = "HKD"
    @State private var settlementAmountString = ""
    @State private var settlementAmountManuallyEdited = false
    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []
    @State private var settlementDirection: AdvanceService.SettlementDirection = .iAdvancedOthers
    @State private var splitLegs: [SplitLeg] = [SplitLeg()]
    @State private var mergeLegs: [MergeLeg] = [MergeLeg()]
    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    private var receiveAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.type != .debt }
    }
    
    private var remaining: Decimal {
        participant.remainingAmount
    }

    private var repaymentAmount: Decimal? {
        positiveDecimal(from: amountString)
    }

    private var isCrossCurrencyRepayment: Bool {
        selectedCurrency.uppercased() != advanceCase.currencyCode.uppercased()
    }
    
    private var directionalCategories: [Category] {
        switch settlementDirection {
        case .iAdvancedOthers:
            return categories.filter { $0.kind.supports(.income) }
        case .othersAdvancedMe:
            return categories.filter { $0.kind.supports(.expense) }
        }
    }

    private var accountLabel: String {
        switch settlementDirection {
        case .iAdvancedOthers:
            return "入帳帳戶"
        case .othersAdvancedMe:
            return "付款帳戶"
        }
    }

    private var categoryLabel: String {
        switch settlementDirection {
        case .iAdvancedOthers:
            return "自己的入帳標記"
        case .othersAdvancedMe:
            return "還款標記（不重複計入支出）"
        }
    }
    
    private var settlementEstimate: CurrencyConversionEstimate? {
        guard let repaymentAmount else { return nil }
        return currencyService.estimate(
            amount: repaymentAmount,
            from: selectedCurrency,
            to: advanceCase.currencyCode
        )
    }

    private var normalSettlementAmount: Decimal? {
        guard let repaymentAmount else { return nil }
        if !isCrossCurrencyRepayment { return repaymentAmount }
        return positiveDecimal(from: settlementAmountString)
    }
    
    private var canSubmit: Bool {
        switch entryMode {
        case .normal:
            return selectedReceiveAccount != nil && repaymentAmount != nil && normalSettlementAmount != nil
        case .split:
            return splitLegs.contains { $0.receiveAccount != nil && positiveDecimal(from: $0.amountString) != nil }
                && splitLegs.allSatisfy { $0.receiveAccount != nil && positiveDecimal(from: $0.amountString) != nil }
        case .merge:
            return selectedReceiveAccount != nil
                && mergeLegs.contains { positiveDecimal(from: $0.amountString) != nil }
                && mergeLegs.allSatisfy { positiveDecimal(from: $0.amountString) != nil }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("模式") {
                    Picker("記錄模式", selection: $entryMode) {
                        ForEach(EntryMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("對象") {
                    summaryRow(title: "姓名", value: participant.name)
                    summaryRow(title: "未還", value: remaining.formatted(.currency(code: advanceCase.currencyCode)))
                }
                
                Section(settlementDirection == .iAdvancedOthers ? "入帳與金額" : "付款與金額") {
                    if entryMode != .split {
                        Picker(accountLabel, selection: $selectedReceiveAccount) {
                            Text("選擇帳戶").tag(nil as Account?)
                            ForEach(receiveAccounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                        .onChange(of: selectedReceiveAccount) { _, _ in
                            if let account = selectedReceiveAccount {
                                selectedCurrency = account.currency
                            }
                        }
                    }
                    
                    switch entryMode {
                    case .normal:
                        HStack {
                            Picker("幣種", selection: $selectedCurrency) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .frame(width: 100)
                            
                            TextField("還款金額", text: Binding(
                                get: { amountString },
                                set: {
                                    amountString = sanitizePositiveDecimalInput($0)
                                    syncSettlementEstimateIfNeeded()
                                }
                            ))
                            .keyboardType(.decimalPad)
                        }
                        
                        if isCrossCurrencyRepayment {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("沖銷代墊金額", text: Binding(
                                        get: { settlementAmountString },
                                        set: {
                                            settlementAmountString = sanitizePositiveDecimalInput($0)
                                            settlementAmountManuallyEdited = true
                                        }
                                    ))
                                    .keyboardType(.decimalPad)

                                    Text(advanceCase.currencyCode)
                                        .foregroundStyle(.secondary)
                                }

                                if let settlementEstimate {
                                    Text("建議 \(settlementEstimate.amount.formatted(.currency(code: advanceCase.currencyCode)))（\(settlementEstimate.source.label)）")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("暫時無法取得匯率，請手動填入要沖銷的 \(advanceCase.currencyCode) 金額。")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else if let settlementEstimate {
                            Text("沖銷 \(settlementEstimate.amount.formatted(.currency(code: advanceCase.currencyCode)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .split:
                        ForEach($splitLegs) { $leg in
                            VStack(spacing: 10) {
                                Picker(accountLabel, selection: $leg.receiveAccount) {
                                    Text("選擇帳戶").tag(nil as Account?)
                                    ForEach(receiveAccounts) { account in
                                        Text(account.name).tag(account as Account?)
                                    }
                                }
                                .onChange(of: leg.receiveAccount) { _, _ in
                                    if let account = leg.receiveAccount {
                                        leg.currency = account.currency
                                    }
                                }
                                
                                HStack {
                                    Picker("幣種", selection: $leg.currency) {
                                        ForEach(currencies, id: \.self) { code in
                                            Text(code).tag(code)
                                        }
                                    }
                                    .frame(width: 100)
                                    
                                    TextField("還款金額", text: Binding(
                                        get: { leg.amountString },
                                        set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                                    ))
                                    .keyboardType(.decimalPad)
                                }
                                
                                if splitLegs.count > 1 {
                                    Button(role: .destructive) {
                                        splitLegs.removeAll { $0.id == leg.id }
                                    } label: {
                                        Text("移除此帳戶")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Button {
                            splitLegs.append(SplitLeg(currency: selectedCurrency))
                        } label: {
                            Label(settlementDirection == .iAdvancedOthers ? "新增分拆入帳帳戶" : "新增分拆付款帳戶", systemImage: "plus.circle")
                        }
                        
                    case .merge:
                        ForEach($mergeLegs) { $leg in
                            HStack {
                                Picker("幣種", selection: $leg.currency) {
                                    ForEach(currencies, id: \.self) { code in
                                        Text(code).tag(code)
                                    }
                                }
                                .frame(width: 100)
                                
                                TextField("還款金額", text: Binding(
                                    get: { leg.amountString },
                                    set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                                ))
                                .keyboardType(.decimalPad)
                            }
                            
                            if mergeLegs.count > 1 {
                                Button(role: .destructive) {
                                    mergeLegs.removeAll { $0.id == leg.id }
                                } label: {
                                    Text("移除此金額項")
                                }
                            }
                        }
                        
                        Button {
                            mergeLegs.append(MergeLeg(currency: selectedCurrency))
                        } label: {
                            Label("新增合併金額項", systemImage: "plus.circle")
                        }
                    }
                }
                
                Section(categoryLabel) {
                    Picker("分類", selection: $selectedCategory) {
                        Text("不設定").tag(nil as Category?)
                        ForEach(directionalCategories) { category in
                            Text(category.name).tag(category as Category?)
                        }
                    }
                    
                    HStack {
                        Text("標籤")
                        Spacer()
                        Button(action: { showingAddTag = true }) {
                            Label("新增", systemImage: "plus")
                                .font(.caption)
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(tags) { tag in
                                let isSelected = selectedTags.contains(tag)
                                Text(tag.name)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .cornerRadius(16)
                                    .onTapGesture {
                                        if isSelected {
                                            selectedTags.remove(tag)
                                        } else {
                                            selectedTags.insert(tag)
                                        }
                                    }
                            }
                        }
                    }
                }
                
                Section("其他") {
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("備註", text: $note)
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("記錄還款")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSubmit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        hideKeyboard()
                    }
                }
            }
            .alert("新增標籤", isPresented: $showingAddTag) {
                TextField("標籤名稱", text: $newTagName)
                Button("取消", role: .cancel) { newTagName = "" }
                Button("新增") { createTag() }
            }
            .alert("無法儲存", isPresented: $showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                Task { await currencyService.fetchRates() }
                settlementDirection = AdvanceService.inferSettlementDirection(
                    for: participant,
                    modelContext: modelContext
                )
                if selectedReceiveAccount == nil, let first = receiveAccounts.first {
                    selectedReceiveAccount = first
                    selectedCurrency = first.currency
                }
                if splitLegs.first?.receiveAccount == nil, let first = receiveAccounts.first {
                    splitLegs[0].receiveAccount = first
                    splitLegs[0].currency = first.currency
                }
                syncSettlementEstimateIfNeeded(force: true)
            }
            .onChange(of: selectedCurrency) { _, _ in
                syncSettlementEstimateIfNeeded()
            }
            .onChange(of: amountString) { _, _ in
                syncSettlementEstimateIfNeeded()
            }
        }
    }
    
    private func save() {
        do {
            switch entryMode {
            case .normal:
                guard let receiveAccount = selectedReceiveAccount else {
                    showError("請選擇\(accountLabel)。")
                    return
                }
                guard let amount = positiveDecimal(from: amountString) else {
                    showError("請輸入大於 0 的還款金額。")
                    return
                }
                guard let normalizedAmount = normalSettlementAmount else {
                    showError("請輸入大於 0 的沖銷金額。")
                    return
                }
                let tolerance = Decimal(string: "0.0001") ?? 0.0001
                guard normalizedAmount - remaining <= tolerance else {
                    showError("沖銷金額超過未還餘額。")
                    return
                }
                
                _ = try recordSingleRepayment(
                    receiveAccount: receiveAccount,
                    amount: amount,
                    currencyCode: selectedCurrency,
                    normalizedAmount: normalizedAmount,
                    note: note,
                    autosave: true
                )
            case .split:
                var legs: [(account: Account, amount: Decimal, currency: String)] = []
                for leg in splitLegs {
                    guard let account = leg.receiveAccount,
                          let amount = positiveDecimal(from: leg.amountString)
                    else {
                        showError("分拆模式下，請為每一項選擇帳戶並填入金額。")
                        return
                    }
                    legs.append((account, amount, leg.currency))
                }
                
                guard let totalIsValid = validateTotalNotExceedingRemaining(items: legs.map { ($0.amount, $0.currency) }) else {
                    showError("暫時無法取得其中一項幣種的匯率，請改用一般模式並手動輸入沖銷金額。")
                    return
                }
                guard totalIsValid else {
                    showError("分拆總金額超過未還餘額。")
                    return
                }
                
                for (index, leg) in legs.enumerated() {
                    _ = try recordSingleRepayment(
                        receiveAccount: leg.account,
                        amount: leg.amount,
                        currencyCode: leg.currency,
                        normalizedAmount: normalizedAmount(for: leg.amount, currency: leg.currency),
                        note: indexedNote(base: note, mode: .split, index: index, count: legs.count),
                        autosave: false
                    )
                }
                try modelContext.save()
                
            case .merge:
                guard let receiveAccount = selectedReceiveAccount else {
                    showError("請選擇\(accountLabel)。")
                    return
                }
                
                var items: [(amount: Decimal, currency: String)] = []
                for leg in mergeLegs {
                    guard let amount = positiveDecimal(from: leg.amountString) else {
                        showError("合併模式下，請為每一項填入金額。")
                        return
                    }
                    items.append((amount, leg.currency))
                }
                
                guard let totalIsValid = validateTotalNotExceedingRemaining(items: items) else {
                    showError("暫時無法取得其中一項幣種的匯率，請改用一般模式並手動輸入沖銷金額。")
                    return
                }
                guard totalIsValid else {
                    showError("合併總金額超過未還餘額。")
                    return
                }
                
                for (index, item) in items.enumerated() {
                    _ = try recordSingleRepayment(
                        receiveAccount: receiveAccount,
                        amount: item.amount,
                        currencyCode: item.currency,
                        normalizedAmount: normalizedAmount(for: item.amount, currency: item.currency),
                        note: indexedNote(base: note, mode: .merge, index: index, count: items.count),
                        autosave: false
                    )
                }
                try modelContext.save()
            }
            
            dismiss()
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
    
    private func sanitizePositiveDecimalInput(_ value: String) -> String {
        let allowed = value.filter { "0123456789.".contains($0) }
        var result = ""
        var hasDot = false
        
        for char in allowed {
            if char == "." {
                if hasDot { continue }
                hasDot = true
            }
            result.append(char)
        }
        
        return result == "." ? "" : result
    }
    
    private func positiveDecimal(from value: String) -> Decimal? {
        guard let parsed = Decimal(string: value), parsed > 0 else { return nil }
        return parsed
    }
    
    private func createTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tag = Tag(name: trimmed)
        modelContext.insert(tag)
        selectedTags.insert(tag)
        newTagName = ""
    }
    
    private func validateTotalNotExceedingRemaining(items: [(amount: Decimal, currency: String)]) -> Bool? {
        var totalNormalized = Decimal.zero
        for item in items {
            guard let normalized = normalizedAmount(for: item.amount, currency: item.currency) else {
                return nil
            }
            totalNormalized += normalized
        }
        let tolerance = Decimal(string: "0.0001") ?? 0.0001
        return totalNormalized - remaining <= tolerance
    }

    private func normalizedAmount(for amount: Decimal, currency: String) -> Decimal? {
        if currency.uppercased() == advanceCase.currencyCode.uppercased() {
            return abs(amount)
        }
        return currencyService.estimate(
            amount: abs(amount),
            from: currency,
            to: advanceCase.currencyCode
        )?.amount
    }
    
    private func recordSingleRepayment(
        receiveAccount: Account,
        amount: Decimal,
        currencyCode: String,
        normalizedAmount: Decimal?,
        note: String,
        autosave: Bool
    ) throws -> AdvanceRepayment {
        guard let normalizedAmount else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }
        return try AdvanceService.recordRepayment(
            advanceCase: advanceCase,
            participant: participant,
            amount: amount,
            currencyCode: currencyCode,
            date: date,
            note: note,
            receiveAccount: receiveAccount,
            category: selectedCategory,
            tags: Array(selectedTags),
            currencyService: currencyService,
            normalizedAmountOverride: normalizedAmount,
            direction: settlementDirection,
            autosave: autosave,
            modelContext: modelContext
        )
    }

    private func syncSettlementEstimateIfNeeded(force: Bool = false) {
        guard force || !settlementAmountManuallyEdited else { return }
        if !isCrossCurrencyRepayment {
            settlementAmountString = amountString
            return
        }
        guard let settlementEstimate else {
            settlementAmountString = ""
            return
        }
        settlementAmountString = NSDecimalNumber(decimal: settlementEstimate.amount).stringValue
    }
    
    private func indexedNote(base: String, mode: EntryMode, index: Int, count: Int) -> String {
        let suffix: String
        switch mode {
        case .split:
            suffix = "[分拆 \(index + 1)/\(count)]"
        case .merge:
            suffix = "[合併 \(index + 1)/\(count)]"
        case .normal:
            suffix = ""
        }
        
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return suffix
        }
        return "\(trimmed) \(suffix)"
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

struct EditAdvanceParticipantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    let advanceCase: AdvanceCase
    let participant: AdvanceParticipant
    
    @State private var name = ""
    @State private var selectedDebtAccount: Account?
    @State private var owedAmountString = ""
    @State private var selectedPaymentAccount: Account?
    @State private var paymentAmountString = ""
    @State private var paymentCurrency = "HKD"
    @State private var direction: AdvanceService.SettlementDirection = .iAdvancedOthers
    @State private var showingError = false
    @State private var errorMessage = ""

    private var ownAccounts: [Account] {
        accounts.filter { !$0.isArchived && $0.type != .debt }
    }

    private var debtAccounts: [Account] {
        accounts.filter { !$0.isArchived && $0.type == .debt }
    }

    private var availableCurrencies: [String] {
        Array(Set(accounts.map(\.currency) + [advanceCase.currencyCode, "HKD", "JPY", "USD", "CNY"]))
            .sorted()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("對象") {
                    TextField("姓名", text: $name)

                    Picker("債務帳戶", selection: $selectedDebtAccount) {
                        Text("請選擇").tag(nil as Account?)
                        ForEach(debtAccounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }

                    HStack {
                        Text("已還")
                        Spacer()
                        Text(participant.repaidAmount.formatted(.currency(code: advanceCase.currencyCode)))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section(direction == .iAdvancedOthers ? "對方欠款" : "我欠對方") {
                    TextField("欠款金額", text: Binding(
                        get: { owedAmountString },
                        set: { owedAmountString = sanitizePositiveDecimalInput($0) }
                    ))
                    .keyboardType(.decimalPad)
                    
                    Text("此金額使用案件幣種 \(advanceCase.currencyCode)，不可低於已還金額。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if direction == .iAdvancedOthers {
                    Section("實際付款") {
                        Picker("付款帳戶", selection: $selectedPaymentAccount) {
                            Text("請選擇").tag(nil as Account?)
                            ForEach(ownAccounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }

                        TextField("實際付款金額", text: Binding(
                            get: { paymentAmountString },
                            set: { paymentAmountString = sanitizePositiveDecimalInput($0) }
                        ))
                        .keyboardType(.decimalPad)

                        Picker("付款幣種", selection: $paymentCurrency) {
                            ForEach(availableCurrencies, id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }

                        Text("付款金額可與欠款金額及案件幣種不同，例如實付 34.86 HKD、朋友欠 710 JPY。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("編輯代墊對象")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        hideKeyboard()
                    }
                }
            }
            .alert("無法儲存", isPresented: $showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                name = participant.name
                selectedDebtAccount = participant.debtAccount
                owedAmountString = NSDecimalNumber(decimal: participant.owedAmount).stringValue
                direction = AdvanceService.inferSettlementDirection(
                    for: participant,
                    modelContext: modelContext
                )
                loadPaymentLeg()
            }
        }
    }
    
    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showError("請輸入對象名稱。")
            return
        }
        guard let debtAccount = selectedDebtAccount else {
            showError("請選擇債務帳戶。")
            return
        }
        guard let newOwed = Decimal(string: owedAmountString), newOwed > 0 else {
            showError("請輸入大於 0 的欠款金額。")
            return
        }

        var paymentAmount: Decimal?
        if direction == .iAdvancedOthers {
            guard selectedPaymentAccount != nil,
                  let parsedPayment = Decimal(string: paymentAmountString),
                  parsedPayment > 0 else {
                showError("請選擇付款帳戶並輸入實際付款金額。")
                return
            }
            paymentAmount = parsedPayment
        }
        
        do {
            try AdvanceService.updateInitialEntry(
                advanceCase: advanceCase,
                participant: participant,
                draft: .init(
                    participantName: trimmedName,
                    debtAccount: debtAccount,
                    payerAccount: direction == .iAdvancedOthers ? selectedPaymentAccount : nil,
                    owedAmount: newOwed,
                    paymentAmount: paymentAmount,
                    paymentCurrencyCode: direction == .iAdvancedOthers ? paymentCurrency : nil,
                    date: advanceCase.date,
                    note: advanceCase.note,
                    category: advanceCase.expenseCategory,
                    tags: tags.filter { advanceCase.tagIDs.contains($0.id) }
                ),
                modelContext: modelContext
            )
            dismiss()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func loadPaymentLeg() {
        guard direction == .iAdvancedOthers,
              let groupID = participant.initialTransferGroupID else {
            return
        }
        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        guard let outgoing = try? modelContext.fetch(descriptor).first(where: {
            $0.advanceEntryRole == .initialAsset
                || $0.transferSide == .outgoing
                || $0.amount < 0
        }) else {
            return
        }
        selectedPaymentAccount = outgoing.account ?? advanceCase.payerAccount
        paymentAmountString = NSDecimalNumber(decimal: abs(outgoing.amount)).stringValue
        paymentCurrency = outgoing.currencyCode
    }
    
    private func sanitizePositiveDecimalInput(_ value: String) -> String {
        let allowed = value.filter { "0123456789.".contains($0) }
        var result = ""
        var hasDot = false
        
        for char in allowed {
            if char == "." {
                if hasDot { continue }
                hasDot = true
            }
            result.append(char)
        }
        
        return result == "." ? "" : result
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
