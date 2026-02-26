import SwiftUI
import SwiftData

struct AdvancesView: View {
    @Query(sort: \AdvanceCase.date, order: .reverse) private var advanceCases: [AdvanceCase]
    @State private var showingAddAdvanceCase = false
    
    private var activeCases: [AdvanceCase] {
        advanceCases.filter { AdvanceService.outstandingAmount(for: $0) > 0 }
    }
    
    private var settledCases: [AdvanceCase] {
        advanceCases.filter { AdvanceService.outstandingAmount(for: $0) == 0 }
    }
    
    var body: some View {
        List {
            if advanceCases.isEmpty {
                Section {
                    ContentUnavailableView(
                        "尚無代墊紀錄",
                        systemImage: "person.2.fill",
                        description: Text("可用右上角加號新增代墊，並追蹤每位對象還款進度。")
                    )
                }
            } else {
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
            }
        }
        .navigationTitle("代墊追蹤")
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
}

struct AdvanceCaseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    
    let advanceCase: AdvanceCase
    @State private var selectedParticipantForRepayment: AdvanceParticipant?
    @State private var selectedParticipantForEdit: AdvanceParticipant?
    @State private var repaymentToRollback: AdvanceRepayment?
    @State private var showingRollbackAlert = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
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
                    title: "待收總額",
                    value: AdvanceService.outstandingAmount(for: advanceCase).formatted(.currency(code: advanceCase.currencyCode))
                )
                summaryRow(
                    title: "付款帳戶",
                    value: advanceCase.payerAccount?.name ?? "未指定"
                )
                summaryRow(
                    title: "帳務儲存",
                    value: "借貸帳戶轉帳"
                )
            }
            
            Section("對象還款狀態") {
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    repaymentToRollback = repayment
                                    showingRollbackAlert = true
                                } label: {
                                    Label("沖銷", systemImage: "arrow.uturn.backward.circle")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(advanceCase.title)
        .sheet(item: $selectedParticipantForRepayment) { participant in
            AddAdvanceRepaymentView(advanceCase: advanceCase, participant: participant)
        }
        .sheet(item: $selectedParticipantForEdit) { participant in
            EditAdvanceParticipantView(advanceCase: advanceCase, participant: participant)
        }
        .alert("確認沖銷還款？", isPresented: $showingRollbackAlert, presenting: repaymentToRollback) { repayment in
            Button("取消", role: .cancel) {}
            Button("沖銷", role: .destructive) {
                rollbackRepayment(repayment)
            }
        } message: { repayment in
            Text("將刪除 \(repayment.amount.formatted(.currency(code: repayment.currencyCode))) 的還款紀錄，並同步刪除對應借貸轉帳。")
        }
        .alert("操作失敗", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
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
                Text("欠款 \(owed.formatted(.currency(code: advanceCase.currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已還 \(repaid.formatted(.currency(code: advanceCase.currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if remaining > 0 {
                HStack(spacing: 8) {
                    Button {
                        selectedParticipantForRepayment = participant
                    } label: {
                        Label("記錄還款", systemImage: "arrow.down.circle")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(repayment.participant?.name ?? "未指定對象")
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Text(repayment.amount.formatted(.currency(code: repayment.currencyCode)))
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            
            HStack(spacing: 6) {
                Text(repayment.date.formatted(date: .abbreviated, time: .shortened))
                Text("•")
                Text("入帳：\(repayment.receivedAccount?.name ?? "未指定")")
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
            try AdvanceService.rollbackRepayment(
                advanceCase: advanceCase,
                repayment: repayment,
                modelContext: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

struct AddAdvanceCaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    
    private struct ParticipantDraft: Identifiable {
        let id = UUID()
        var debtAccount: Account?
        var amountString: String = ""
    }
    
    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var myShareString = ""
    @State private var selectedCurrency = "HKD"
    @State private var selectedPayerAccount: Account?
    @State private var selectedCategory: Category?
    @State private var participantDrafts: [ParticipantDraft] = [ParticipantDraft()]
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    private var myAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.type != .debt }
    }
    
    private var debtAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.type == .debt }
    }
    
    private var expenseCategories: [Category] {
        categories.filter { $0.kind.supports(.expense) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("代墊名稱 (例如：聚餐 2026-03-01)", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("付款帳戶", selection: $selectedPayerAccount) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(myAccounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    .onChange(of: selectedPayerAccount) {
                        if let account = selectedPayerAccount {
                            selectedCurrency = account.currency
                        }
                    }
                    
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
                
                Section("自己的份額") {
                    TextField("0 (可留空)", text: Binding(
                        get: { myShareString },
                        set: { myShareString = sanitizePositiveDecimalInput($0) }
                    ))
                    .keyboardType(.decimalPad)
                    
                    Picker("支出分類", selection: $selectedCategory) {
                        Text("不設定").tag(nil as Category?)
                        ForEach(expenseCategories) { category in
                            Text(category.name).tag(category as Category?)
                        }
                    }
                }
                
                Section("代墊對象") {
                    if debtAccounts.isEmpty {
                        Text("請先在「帳戶」新增類型為「借貸/債務」的對象帳戶。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        ForEach($participantDrafts) { $draft in
                            VStack(spacing: 10) {
                                Picker("對象", selection: $draft.debtAccount) {
                                    Text("選擇對象").tag(nil as Account?)
                                    ForEach(debtAccounts) { account in
                                        Text(account.name).tag(account as Account?)
                                    }
                                }
                                
                                TextField("代墊金額", text: Binding(
                                    get: { draft.amountString },
                                    set: { draft.amountString = sanitizePositiveDecimalInput($0) }
                                ))
                                .keyboardType(.decimalPad)
                                
                                if participantDrafts.count > 1 {
                                    Button(role: .destructive) {
                                        participantDrafts.removeAll { $0.id == draft.id }
                                    } label: {
                                        Text("移除此對象")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Button {
                            participantDrafts.append(ParticipantDraft())
                        } label: {
                            Label("新增對象", systemImage: "plus.circle")
                        }
                    }
                }
                
                Section("備註") {
                    TextField("可填入店名、說明等", text: $note)
                }
            }
            .navigationTitle("新增代墊")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(selectedPayerAccount == nil || debtAccounts.isEmpty)
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
                if selectedPayerAccount == nil, let first = myAccounts.first {
                    selectedPayerAccount = first
                    selectedCurrency = first.currency
                }
            }
        }
    }
    
    private func save() {
        guard let payer = selectedPayerAccount else {
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
                myShareAmount: myShare,
                note: note,
                payerAccount: payer,
                category: selectedCategory,
                participants: participantInputs,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            showError(error.localizedDescription)
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
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

struct AddAdvanceRepaymentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @StateObject private var currencyService = CurrencyService.shared
    
    let advanceCase: AdvanceCase
    let participant: AdvanceParticipant
    
    @State private var selectedReceiveAccount: Account?
    @State private var amountString = ""
    @State private var selectedCurrency = "HKD"
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
    
    private var convertedPreview: Decimal? {
        guard let amount = Decimal(string: amountString), amount > 0 else { return nil }
        return currencyService.convert(amount: amount, from: selectedCurrency, to: advanceCase.currencyCode)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("對象") {
                    summaryRow(title: "姓名", value: participant.name)
                    summaryRow(title: "未還", value: remaining.formatted(.currency(code: advanceCase.currencyCode)))
                }
                
                Section("入帳與金額") {
                    Picker("入帳帳戶", selection: $selectedReceiveAccount) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(receiveAccounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    .onChange(of: selectedReceiveAccount) {
                        if let account = selectedReceiveAccount {
                            selectedCurrency = account.currency
                        }
                    }
                    
                    HStack {
                        Picker("幣種", selection: $selectedCurrency) {
                            ForEach(currencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .frame(width: 100)
                        
                        TextField("還款金額", text: Binding(
                            get: { amountString },
                            set: { amountString = sanitizePositiveDecimalInput($0) }
                        ))
                        .keyboardType(.decimalPad)
                    }
                    
                    if let convertedPreview {
                        Text("折算為 \(convertedPreview.formatted(.currency(code: advanceCase.currencyCode)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("其他") {
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("備註", text: $note)
                }
            }
            .navigationTitle("記錄還款")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(selectedReceiveAccount == nil || amountString.isEmpty)
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
                Task { await currencyService.fetchRates() }
                if selectedReceiveAccount == nil, let first = receiveAccounts.first {
                    selectedReceiveAccount = first
                    selectedCurrency = first.currency
                }
            }
        }
    }
    
    private func save() {
        guard let receiveAccount = selectedReceiveAccount else {
            showError("請選擇入帳帳戶。")
            return
        }
        guard let amount = Decimal(string: amountString), amount > 0 else {
            showError("請輸入大於 0 的還款金額。")
            return
        }
        
        do {
            _ = try AdvanceService.recordRepayment(
                advanceCase: advanceCase,
                participant: participant,
                amount: amount,
                currencyCode: selectedCurrency,
                date: date,
                note: note,
                receiveAccount: receiveAccount,
                currencyService: currencyService,
                modelContext: modelContext
            )
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
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

struct EditAdvanceParticipantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let advanceCase: AdvanceCase
    let participant: AdvanceParticipant
    
    @State private var owedAmountString = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("對象") {
                    HStack {
                        Text("姓名")
                        Spacer()
                        Text(participant.name)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("已還")
                        Spacer()
                        Text(participant.repaidAmount.formatted(.currency(code: advanceCase.currencyCode)))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("更正欠款") {
                    TextField("欠款金額", text: Binding(
                        get: { owedAmountString },
                        set: { owedAmountString = sanitizePositiveDecimalInput($0) }
                    ))
                    .keyboardType(.decimalPad)
                    
                    Text("此值用於代墊追蹤；借貸實際帳務仍以轉帳紀錄為準。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("更正欠款")
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
                owedAmountString = NSDecimalNumber(decimal: participant.owedAmount).stringValue
            }
        }
    }
    
    private func save() {
        guard let newOwed = Decimal(string: owedAmountString), newOwed > 0 else {
            showError("請輸入大於 0 的欠款金額。")
            return
        }
        
        do {
            try AdvanceService.updateParticipantOwedAmount(
                advanceCase: advanceCase,
                participant: participant,
                newOwedAmount: newOwed,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            showError(error.localizedDescription)
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
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
