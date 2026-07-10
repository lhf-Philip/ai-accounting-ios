import SwiftData
import SwiftUI

struct AdvanceStructuralEditorView: View {
    fileprivate struct PaymentLegState: Identifiable {
        let id: UUID
        let transactionID: UUID?
        var account: Account?
        var amount = ""
        var currencyCode = "HKD"

        init(
            id: UUID = UUID(),
            transactionID: UUID? = nil,
            account: Account? = nil,
            amount: String = "",
            currencyCode: String = "HKD"
        ) {
            self.id = id
            self.transactionID = transactionID
            self.account = account
            self.amount = amount
            self.currencyCode = currencyCode
        }
    }

    fileprivate struct ParticipantState: Identifiable {
        let id: UUID
        let participant: AdvanceParticipant?
        var name: String
        var debtAccount: Account?
        var owedAmount: String
        var paymentLegs: [PaymentLegState]

        init(
            id: UUID = UUID(),
            participant: AdvanceParticipant? = nil,
            name: String = "",
            debtAccount: Account? = nil,
            owedAmount: String = "",
            paymentLegs: [PaymentLegState] = []
        ) {
            self.id = id
            self.participant = participant
            self.name = name
            self.debtAccount = debtAccount
            self.owedAmount = owedAmount
            self.paymentLegs = paymentLegs
        }
    }

    fileprivate struct RepaymentState: Identifiable {
        let id: UUID
        let repayment: AdvanceRepayment
        let participantID: UUID
        var account: Account?
        var amount: String
        var currencyCode: String
        var normalizedAmount: String
        var date: Date
        var note: String
        var category: Category?
        var tags: Set<Tag>
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var transactions: [FinancialTransaction]

    let advanceCase: AdvanceCase

    @State private var title = ""
    @State private var date = Date()
    @State private var direction: AdvanceDirection = .iAdvancedOthers
    @State private var currencyCode = "HKD"
    @State private var note = ""
    @State private var category: Category?
    @State private var selectedTags: Set<Tag> = []
    @State private var includesShare = false
    @State private var shareAccount: Account?
    @State private var shareAmount = ""
    @State private var shareCurrency = "HKD"
    @State private var shareNormalizedAmount = ""
    @State private var participants: [ParticipantState] = []
    @State private var repayments: [RepaymentState] = []
    @State private var confirmsCurrencyAmounts = true
    @State private var pendingDraft: AdvanceCaseEditDraft?
    @State private var pendingPreview: AdvanceCaseImpactPreview?
    @State private var showingImpactPreview = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private let commonCurrencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var ownAccounts: [Account] {
        accounts.filter { !$0.isArchived && $0.type != .debt }
    }

    private var debtAccounts: [Account] {
        accounts.filter { !$0.isArchived && $0.type == .debt }
    }

    private var availableCurrencies: [String] {
        Array(Set(commonCurrencies + accounts.map(\.currency) + [advanceCase.currencyCode]))
            .sorted()
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.kind.supports(.expense) }
    }

    private var repaymentCategories: [Category] {
        let type: TransactionType = direction == .iAdvancedOthers ? .income : .expense
        return categories.filter { $0.kind.supports(type) }
    }

    private var hasSpecialRepayments: Bool {
        advanceCase.repayments.contains {
            AdvanceSemantics.repaymentRecordKind(note: $0.note) != .ordinary
        }
    }

    private var hasChangedCaseCurrency: Bool {
        currencyCode.caseInsensitiveCompare(advanceCase.currencyCode) != .orderedSame
    }

    private var impactMessage: String {
        guard let preview = pendingPreview else { return "" }
        var lines = preview.warnings
        lines.append("將重建或更新 \(preview.affectedTransactionCount) 筆底層分錄。")
        if preview.removedParticipantCount > 0 {
            lines.append("將刪除 \(preview.removedParticipantCount) 位參與人。")
        }
        if preview.removedRepaymentCount > 0 {
            lines.append("將刪除 \(preview.removedRepaymentCount) 筆還款。")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                caseSection
                shareSection
                participantsSection
                repaymentsSection
                confirmationSection
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("完整編輯代墊")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("預覽影響", action: previewAndConfirm)
                        .disabled(hasSpecialRepayments)
                        .accessibilityIdentifier("advance.structural.preview")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
            .alert("確認套用結構性變更？", isPresented: $showingImpactPreview) {
                Button("取消", role: .cancel) {
                    pendingDraft = nil
                    pendingPreview = nil
                }
                Button("確認重建", role: .destructive, action: applyPendingDraft)
                    .accessibilityIdentifier("advance.structural.apply")
            } message: {
                Text(impactMessage)
            }
            .alert("無法編輯", isPresented: $showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear(perform: load)
            .onChange(of: currencyCode) { _, newValue in
                confirmsCurrencyAmounts =
                    newValue.caseInsensitiveCompare(advanceCase.currencyCode) == .orderedSame
            }
            .onChange(of: direction) { _, newValue in
                if newValue == .othersAdvancedMe {
                    includesShare = false
                    for index in participants.indices {
                        participants[index].paymentLegs = []
                    }
                } else {
                    for index in participants.indices where participants[index].paymentLegs.isEmpty {
                        participants[index].paymentLegs = [
                            PaymentLegState(
                                account: ownAccounts.first,
                                currencyCode: ownAccounts.first?.currency ?? currencyCode
                            )
                        ]
                    }
                }
                if let category, !expenseCategories.contains(where: { $0.id == category.id }) {
                    self.category = nil
                }
                for index in repayments.indices {
                    if let selected = repayments[index].category,
                       !repaymentCategories.contains(where: { $0.id == selected.id }) {
                        repayments[index].category = nil
                    }
                }
            }
        }
    }

    private var caseSection: some View {
        Section("案件") {
            Picker("方向", selection: $direction) {
                Text("我代墊他人").tag(AdvanceDirection.iAdvancedOthers)
                Text("他人代墊我").tag(AdvanceDirection.othersAdvancedMe)
            }
            .pickerStyle(.segmented)

            TextField("案件名稱", text: $title)
                .accessibilityIdentifier("advance.structural.title")
            DatePicker("日期", selection: $date)
            Picker("案件幣種", selection: $currencyCode) {
                ForEach(availableCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .accessibilityIdentifier("advance.structural.currency")

            Picker("支出分類", selection: $category) {
                Text("無分類").tag(nil as Category?)
                ForEach(expenseCategories) { item in
                    Text(item.name).tag(item as Category?)
                }
            }

            TagSelection(tags: tags, selected: $selectedTags)

            TextField("備註", text: $note)
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        if direction == .iAdvancedOthers {
            Section("自己的份額") {
                Toggle("包含自己的份額", isOn: $includesShare)
                if includesShare {
                    Picker("付款帳戶", selection: $shareAccount) {
                        Text("請選擇").tag(nil as Account?)
                        ForEach(ownAccounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    AmountCurrencyRow(
                        amount: $shareAmount,
                        currency: $shareCurrency,
                        currencies: availableCurrencies,
                        label: "實際付款"
                    )
                    TextField(
                        "案件份額 \(currencyCode)",
                        text: decimalBinding($shareNormalizedAmount)
                    )
                    .keyboardType(.decimalPad)
                    Text("實際付款與案件份額都必須明確確認，不會自動套用匯率。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var participantsSection: some View {
        Section {
            ForEach($participants) { $participant in
                ParticipantEditor(
                    participant: $participant,
                    direction: direction,
                    caseCurrency: currencyCode,
                    ownAccounts: ownAccounts,
                    debtAccounts: debtAccounts,
                    currencies: availableCurrencies,
                    canRemove: participants.count > 1,
                    onAddPaymentLeg: {
                        participant.paymentLegs.append(
                            PaymentLegState(
                                account: ownAccounts.first,
                                currencyCode: ownAccounts.first?.currency ?? currencyCode
                            )
                        )
                    },
                    onRemovePaymentLeg: { legID in
                        participant.paymentLegs.removeAll { $0.id == legID }
                    },
                    onRemove: {
                        removeParticipant(participant.id)
                    }
                )
            }

            Button {
                participants.append(
                    ParticipantState(
                        paymentLegs: direction == .iAdvancedOthers
                            ? [
                                PaymentLegState(
                                    account: ownAccounts.first,
                                    currencyCode: ownAccounts.first?.currency ?? currencyCode
                                )
                            ]
                            : []
                    )
                )
            } label: {
                Label("新增參與人", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("advance.structural.addParticipant")
        } header: {
            Text(direction == .iAdvancedOthers ? "代墊對象與付款來源" : "我欠的人")
        } footer: {
            Text("刪除已有還款的參與人時，下一步會列出影響並要求再次確認。")
        }
    }

    private var repaymentsSection: some View {
        Section {
            if repayments.isEmpty {
                Text("沒有可編輯的普通還款。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($repayments) { $repayment in
                    RepaymentEditor(
                        repayment: $repayment,
                        participantName: participantName(for: repayment.participantID),
                        accounts: ownAccounts,
                        categories: repaymentCategories,
                        tags: tags,
                        currencies: availableCurrencies,
                        caseCurrency: currencyCode
                    )
                }
            }
        } header: {
            Text("普通還款沖銷")
        } footer: {
            Text("改變案件幣種時，每筆沖銷額都必須重新確認。")
        }
    }

    private var confirmationSection: some View {
        Section("安全確認") {
            if hasSpecialRepayments {
                Label(
                    "此案件含債務抵銷或手動結清。請返回詳情先整組撤銷，才能進行結構性編輯。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
            if hasChangedCaseCurrency {
                Toggle(
                    "我已重新確認所有 \(currencyCode) 案件金額與還款沖銷額",
                    isOn: $confirmsCurrencyAmounts
                )
                .accessibilityIdentifier("advance.structural.confirmCurrency")
            }
            Text("儲存前會先顯示影響預覽；確認後才原子重建，任何失敗都不會留下部分變更。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func load() {
        title = advanceCase.title
        date = advanceCase.date
        direction = advanceCase.direction ?? .iAdvancedOthers
        currencyCode = advanceCase.currencyCode
        note = advanceCase.note
        category = advanceCase.expenseCategory
        let caseTagIDs = advanceCase.tagIDs ?? []
        selectedTags = Set(tags.filter { caseTagIDs.contains($0.id) })

        if let shareID = advanceCase.selfExpenseTransactionID,
           let transaction = transactions.first(where: { $0.id == shareID }) {
            includesShare = true
            shareAccount = transaction.account
            shareAmount = decimalString(abs(transaction.amount))
            shareCurrency = transaction.currencyCode
            shareNormalizedAmount = decimalString(advanceCase.myShareAmount)
        } else {
            includesShare = false
            shareAccount = ownAccounts.first
            shareCurrency = ownAccounts.first?.currency ?? advanceCase.currencyCode
        }

        participants = advanceCase.participants
            .sorted { $0.createdAt < $1.createdAt }
            .map { participant in
                let group = participant.initialTransferGroupID.map(transactionsForGroup) ?? []
                let legs = group
                    .filter { $0.advanceEntryRole == .initialAsset }
                    .map {
                        PaymentLegState(
                            transactionID: $0.id,
                            account: $0.account,
                            amount: decimalString(abs($0.amount)),
                            currencyCode: $0.currencyCode
                        )
                    }
                return ParticipantState(
                    id: participant.id,
                    participant: participant,
                    name: participant.name,
                    debtAccount: participant.debtAccount,
                    owedAmount: decimalString(participant.owedAmount),
                    paymentLegs: direction == .iAdvancedOthers ? legs : []
                )
            }

        repayments = advanceCase.repayments
            .filter { AdvanceSemantics.repaymentRecordKind(note: $0.note) == .ordinary }
            .sorted { $0.date < $1.date }
            .compactMap { repayment in
                guard let participantID = repayment.participant?.id else { return nil }
                let group = repayment.linkedTransferGroupID.map(transactionsForGroup) ?? []
                let ownLeg = group.first { $0.advanceEntryRole == .repaymentAsset }
                return RepaymentState(
                    id: repayment.id,
                    repayment: repayment,
                    participantID: participantID,
                    account: repayment.receivedAccount,
                    amount: decimalString(repayment.amount),
                    currencyCode: repayment.currencyCode,
                    normalizedAmount: decimalString(repayment.normalizedAmount),
                    date: repayment.date,
                    note: repayment.note,
                    category: ownLeg?.category,
                    tags: Set(ownLeg?.tags ?? [])
                )
            }
    }

    private func previewAndConfirm() {
        guard !hasChangedCaseCurrency || confirmsCurrencyAmounts else {
            showError("請先確認新案件幣種下的所有金額與還款沖銷額。")
            return
        }
        do {
            let draft = try makeDraft()
            pendingPreview = try AdvanceCaseEditingService.preview(
                draft,
                modelContext: modelContext
            )
            pendingDraft = draft
            showingImpactPreview = true
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func applyPendingDraft() {
        guard let pendingDraft else { return }
        do {
            try AdvanceCaseEditingService.apply(pendingDraft, modelContext: modelContext)
            dismiss()
        } catch {
            showError(error.localizedDescription)
        }
        self.pendingDraft = nil
        pendingPreview = nil
    }

    private func makeDraft() throws -> AdvanceCaseEditDraft {
        let participantDrafts = try participants.map { participant -> AdvanceParticipantDraft in
            guard let debtAccount = participant.debtAccount else {
                throw AdvanceCaseEditingError.invalidDebtAccount
            }
            guard let owedAmount = positiveDecimal(participant.owedAmount) else {
                throw AdvanceServiceError.invalidAdjustedOwedAmount
            }
            let paymentLegs: [AdvancePaymentLegDraft]
            if direction == .iAdvancedOthers {
                paymentLegs = try participant.paymentLegs.map { leg in
                    guard let account = leg.account,
                          let amount = positiveDecimal(leg.amount)
                    else {
                        throw AdvanceCaseEditingError.invalidPaymentLeg
                    }
                    return AdvancePaymentLegDraft(
                        transactionID: leg.transactionID,
                        account: account,
                        amount: amount,
                        currencyCode: leg.currencyCode
                    )
                }
            } else {
                paymentLegs = []
            }
            return AdvanceParticipantDraft(
                participant: participant.participant,
                name: participant.name,
                debtAccount: debtAccount,
                owedAmount: owedAmount,
                paymentLegs: paymentLegs
            )
        }

        let repaymentDrafts = try repayments.map { state -> AdvanceRepaymentDraft in
            guard participants.contains(where: {
                $0.participant?.id == state.participantID
            }) else {
                throw AdvanceCaseEditingError.repaymentNotInCase
            }
            guard let account = state.account,
                  let amount = positiveDecimal(state.amount),
                  let normalizedAmount = positiveDecimal(state.normalizedAmount)
            else {
                throw AdvanceServiceError.invalidRepaymentAmount
            }
            return AdvanceRepaymentDraft(
                repayment: state.repayment,
                account: account,
                amount: amount,
                currencyCode: state.currencyCode,
                normalizedAmount: normalizedAmount,
                date: state.date,
                note: state.note,
                category: state.category,
                tags: Array(state.tags)
            )
        }

        let shareDraft: AdvanceShareDraft?
        if direction == .iAdvancedOthers, includesShare {
            guard let account = shareAccount,
                  let amount = positiveDecimal(shareAmount),
                  let normalizedAmount = positiveDecimal(shareNormalizedAmount)
            else {
                throw AdvanceCaseEditingError.invalidShare
            }
            shareDraft = AdvanceShareDraft(
                transactionID: advanceCase.selfExpenseTransactionID,
                account: account,
                amount: amount,
                normalizedAmount: normalizedAmount,
                currencyCode: shareCurrency
            )
        } else {
            shareDraft = nil
        }

        return AdvanceCaseEditDraft(
            advanceCase: advanceCase,
            title: title,
            date: date,
            direction: direction,
            currencyCode: currencyCode,
            note: note,
            category: category,
            tags: Array(selectedTags),
            share: shareDraft,
            participants: participantDrafts,
            repayments: repaymentDrafts
        )
    }

    private func removeParticipant(_ id: UUID) {
        guard participants.count > 1 else { return }
        let participantID = participants.first(where: { $0.id == id })?.participant?.id
        participants.removeAll { $0.id == id }
        if let participantID {
            repayments.removeAll { $0.participantID == participantID }
        }
    }

    private func transactionsForGroup(_ groupID: UUID) -> [FinancialTransaction] {
        transactions.filter { $0.transferGroupID == groupID }
    }

    private func participantName(for participantID: UUID) -> String {
        participants.first(where: {
            $0.participant?.id == participantID
        })?.name ?? "已移除對象"
    }

    private func decimalBinding(_ value: Binding<String>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = sanitizeDecimal($0) }
        )
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

private struct ParticipantEditor: View {
    @Binding var participant: AdvanceStructuralEditorView.ParticipantState
    let direction: AdvanceDirection
    let caseCurrency: String
    let ownAccounts: [Account]
    let debtAccounts: [Account]
    let currencies: [String]
    let canRemove: Bool
    let onAddPaymentLeg: () -> Void
    let onRemovePaymentLeg: (UUID) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("姓名", text: $participant.name)
                .accessibilityIdentifier("advance.structural.participantName")
            Picker("債務帳戶", selection: $participant.debtAccount) {
                Text("請選擇").tag(nil as Account?)
                ForEach(debtAccounts) { account in
                    Text(account.name).tag(account as Account?)
                }
            }
            TextField(
                "\(caseCurrency) 欠款金額",
                text: Binding(
                    get: { participant.owedAmount },
                    set: { participant.owedAmount = sanitizeDecimal($0) }
                )
            )
            .keyboardType(.decimalPad)

            if direction == .iAdvancedOthers {
                ForEach($participant.paymentLegs) { $leg in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("付款帳戶", selection: $leg.account) {
                            Text("請選擇").tag(nil as Account?)
                            ForEach(ownAccounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                        AmountCurrencyRow(
                            amount: $leg.amount,
                            currency: $leg.currencyCode,
                            currencies: currencies,
                            label: "實際付款"
                        )
                        if participant.paymentLegs.count > 1 {
                            Button("刪除此付款來源", role: .destructive) {
                                onRemovePaymentLeg(leg.id)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("advance.structural.removePaymentLeg")
                        }
                    }
                    .padding(.leading, 12)
                    .accessibilityIdentifier("advance.structural.paymentLeg")
                }
                Button("新增付款來源", action: onAddPaymentLeg)
                    .accessibilityIdentifier("advance.structural.addPaymentLeg")
            }

            if canRemove {
                Button("刪除此參與人", role: .destructive, action: onRemove)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("advance.structural.removeParticipant")
            }
        }
        .padding(.vertical, 6)
    }
}

private struct RepaymentEditor: View {
    @Binding var repayment: AdvanceStructuralEditorView.RepaymentState
    let participantName: String
    let accounts: [Account]
    let categories: [Category]
    let tags: [Tag]
    let currencies: [String]
    let caseCurrency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(participantName)
                .font(.headline)
            Picker("帳戶", selection: $repayment.account) {
                Text("請選擇").tag(nil as Account?)
                ForEach(accounts) { account in
                    Text(account.name).tag(account as Account?)
                }
            }
            AmountCurrencyRow(
                amount: $repayment.amount,
                currency: $repayment.currencyCode,
                currencies: currencies,
                label: "實際還款"
            )
            TextField(
                "\(caseCurrency) 沖銷額",
                text: Binding(
                    get: { repayment.normalizedAmount },
                    set: { repayment.normalizedAmount = sanitizeDecimal($0) }
                )
            )
            .keyboardType(.decimalPad)
            DatePicker("日期", selection: $repayment.date)
            Picker("分類", selection: $repayment.category) {
                Text("無分類").tag(nil as Category?)
                ForEach(categories) { category in
                    Text(category.name).tag(category as Category?)
                }
            }
            TagSelection(tags: tags, selected: $repayment.tags)
            TextField("備註", text: $repayment.note)
        }
        .padding(.vertical, 6)
    }
}

private struct AmountCurrencyRow: View {
    @Binding var amount: String
    @Binding var currency: String
    let currencies: [String]
    let label: String

    var body: some View {
        HStack {
            TextField(
                label,
                text: Binding(
                    get: { amount },
                    set: { amount = sanitizeDecimal($0) }
                )
            )
            .keyboardType(.decimalPad)
            Picker("幣種", selection: $currency) {
                ForEach(currencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
        }
    }
}

private struct TagSelection: View {
    let tags: [Tag]
    @Binding var selected: Set<Tag>

    var body: some View {
        ForEach(tags) { tag in
            Toggle(
                tag.name,
                isOn: Binding(
                    get: { selected.contains(tag) },
                    set: { isSelected in
                        if isSelected {
                            selected.insert(tag)
                        } else {
                            selected.remove(tag)
                        }
                    }
                )
            )
        }
    }
}

private func sanitizeDecimal(_ value: String) -> String {
    let allowed = value.filter { $0.isNumber || $0 == "." }
    var result = ""
    var hasDot = false
    for character in allowed {
        if character == "." {
            if hasDot { continue }
            hasDot = true
        }
        result.append(character)
    }
    return result == "." ? "" : result
}

private func positiveDecimal(_ value: String) -> Decimal? {
    Decimal(string: value).flatMap { $0 > 0 ? $0 : nil }
}

private func decimalString(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}
