import SwiftUI
import SwiftData

struct EditTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyService = CurrencyService.shared

    let originalTransaction: FinancialTransaction

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var advanceParticipants: [AdvanceParticipant]
    @Query private var advanceRepayments: [AdvanceRepayment]

    private struct TransferLegInput: Identifiable {
        let id: UUID
        var transaction: FinancialTransaction?
        var account: Account?
        var currency: String
        var amountString: String

        init(
            id: UUID = UUID(),
            transaction: FinancialTransaction?,
            account: Account?,
            currency: String,
            amountString: String
        ) {
            self.id = id
            self.transaction = transaction
            self.account = account
            self.currency = currency
            self.amountString = amountString
        }
    }

    private struct DesiredLeg {
        let account: Account
        let currency: String
        let amount: Decimal
    }

    @State private var outgoingLegs: [TransferLegInput] = []
    @State private var incomingLegs: [TransferLegInput] = []
    @State private var date: Date = Date()
    @State private var note: String = ""

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingValidationAlert = false
    @State private var validationMessage: String = ""

    @FocusState private var focusedFieldID: UUID?

    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var canSubmit: Bool {
        !isLoading
            && !outgoingLegs.isEmpty
            && !incomingLegs.isEmpty
            && outgoingLegs.allSatisfy { $0.account != nil && positiveDecimal(from: $0.amountString) != nil }
            && incomingLegs.allSatisfy { $0.account != nil && positiveDecimal(from: $0.amountString) != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("載入轉帳中...")
                } else if let errorMessage {
                    Text("無法編輯：\(errorMessage)")
                        .foregroundStyle(.red)
                } else {
                    Section("轉出方") {
                        ForEach($outgoingLegs) { $leg in
                            VStack(spacing: 10) {
                                Picker("從帳戶", selection: $leg.account) {
                                    Text("選擇帳戶").tag(nil as Account?)
                                    ForEach(activeAccounts) { account in
                                        Text(account.name).tag(account as Account?)
                                    }
                                }
                                .onChange(of: leg.account) { _, newValue in
                                    guard let newValue else { return }
                                    leg.currency = newValue.currency
                                }

                                HStack {
                                    Picker("幣種", selection: $leg.currency) {
                                        ForEach(currencies, id: \.self) { code in
                                            Text(code).tag(code)
                                        }
                                    }
                                    .frame(width: 110)

                                    TextField("轉出金額", text: Binding(
                                        get: { leg.amountString },
                                        set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .focused($focusedFieldID, equals: leg.id)
                                }

                                if outgoingLegs.count > 1 {
                                    Button(role: .destructive) {
                                        outgoingLegs.removeAll { $0.id == leg.id }
                                    } label: {
                                        Text("移除此轉出項")
                                    }
                                }
                            }
                            .padding(.vertical, 4)

                            CurrencyRateHintView(
                                currencyService: currencyService,
                                amount: positiveDecimal(from: leg.amountString),
                                currencyCode: leg.currency
                            )
                        }

                        Button {
                            outgoingLegs.append(
                                TransferLegInput(
                                    transaction: nil,
                                    account: nil,
                                    currency: "HKD",
                                    amountString: ""
                                )
                            )
                        } label: {
                            Label("新增轉出項", systemImage: "plus.circle")
                        }
                    }

                    Section("轉入方") {
                        ForEach($incomingLegs) { $leg in
                            VStack(spacing: 10) {
                                Picker("到帳戶", selection: $leg.account) {
                                    Text("選擇帳戶").tag(nil as Account?)
                                    ForEach(activeAccounts) { account in
                                        Text(account.name).tag(account as Account?)
                                    }
                                }
                                .onChange(of: leg.account) { _, newValue in
                                    guard let newValue else { return }
                                    leg.currency = newValue.currency
                                }

                                HStack {
                                    Picker("幣種", selection: $leg.currency) {
                                        ForEach(currencies, id: \.self) { code in
                                            Text(code).tag(code)
                                        }
                                    }
                                    .frame(width: 110)

                                    TextField("轉入金額", text: Binding(
                                        get: { leg.amountString },
                                        set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .focused($focusedFieldID, equals: leg.id)
                                }

                                if incomingLegs.count > 1 {
                                    Button(role: .destructive) {
                                        incomingLegs.removeAll { $0.id == leg.id }
                                    } label: {
                                        Text("移除此轉入項")
                                    }
                                }
                            }
                            .padding(.vertical, 4)

                            CurrencyRateHintView(
                                currencyService: currencyService,
                                amount: positiveDecimal(from: leg.amountString),
                                currencyCode: leg.currency
                            )
                        }

                        Button {
                            incomingLegs.append(
                                TransferLegInput(
                                    transaction: nil,
                                    account: nil,
                                    currency: "HKD",
                                    amountString: ""
                                )
                            )
                        } label: {
                            Label("新增轉入項", systemImage: "plus.circle")
                        }
                    }

                    Section("其他") {
                        DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("transferEditor.datePicker")
                        TextField("備註", text: $note)
                            .accessibilityIdentifier("transferEditor.noteField")
                        if outgoingLegs.count == 1, incomingLegs.count == 1 {
                            TransferRateHintView(
                                currencyService: currencyService,
                                outgoingAmount: positiveDecimal(from: outgoingLegs[0].amountString),
                                outgoingCurrency: outgoingLegs[0].currency,
                                incomingAmount: positiveDecimal(from: incomingLegs[0].amountString),
                                incomingCurrency: incomingLegs[0].currency
                            )
                        }
                    }
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("編輯轉帳")
            .alert("輸入錯誤", isPresented: $showingValidationAlert) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveChanges() }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("transferEditor.saveButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedFieldID = nil }
                }
            }
            .onAppear {
                loadData()
                Task { await currencyService.fetchRates() }
            }
        }
    }

    private func loadData() {
        do {
            let groupTransactions = try fetchGroupTransactions(for: originalTransaction)
                .filter { $0.type == .transfer }

            guard !groupTransactions.isEmpty else {
                errorMessage = "找不到可編輯的轉帳資料。"
                isLoading = false
                return
            }
            let semantic = TransferEditRoutingService.classify(
                transaction: originalTransaction,
                groupTransactions: groupTransactions,
                advanceInitialGroupIDs: Set(advanceParticipants.compactMap(\.initialTransferGroupID)),
                advanceRepaymentGroupIDs: Set(advanceRepayments.compactMap(\.linkedTransferGroupID))
            )
            guard semantic == .ordinary else {
                switch semantic {
                case .debt:
                    errorMessage = "這是債務管理分錄，請從債務管理編輯。"
                case .debtForgiveness:
                    errorMessage = "這是免除債務紀錄，請從債務管理編輯。"
                case .advanceInitial, .advanceRepayment:
                    errorMessage = "這是代墊關聯分錄，請從代墊詳情編輯。"
                case .ordinary:
                    break
                }
                isLoading = false
                return
            }

            let outgoing = groupTransactions.filter { isOutgoing($0) }
            let incoming = groupTransactions.filter { !isOutgoing($0) }

            outgoingLegs = outgoing.map(makeLeg(from:))
            incomingLegs = incoming.map(makeLeg(from:))

            if outgoingLegs.isEmpty {
                outgoingLegs = [
                    TransferLegInput(
                        transaction: nil,
                        account: originalTransaction.account,
                        currency: defaultCurrency(for: originalTransaction),
                        amountString: decimalString(from: abs(originalTransaction.amount))
                    )
                ]
            }

            if incomingLegs.isEmpty {
                incomingLegs = [
                    TransferLegInput(
                        transaction: nil,
                        account: nil,
                        currency: defaultCurrency(for: nil),
                        amountString: decimalString(from: abs(originalTransaction.amount))
                    )
                ]
            }

            date = originalTransaction.date
            note = extractMemo(from: originalTransaction.note)
            isLoading = false
        } catch {
            errorMessage = "讀取錯誤：\(error.localizedDescription)"
            isLoading = false
        }
    }

    private func saveChanges() {
        do {
            let parsedOutgoing = try parseLegs(from: outgoingLegs, sideName: "轉出")
            let parsedIncoming = try parseLegs(from: incomingLegs, sideName: "轉入")

            let outgoingIdentities = parsedOutgoing.map {
                TransferLegIdentity(accountID: $0.account.id, currencyCode: $0.currency)
            }
            let incomingIdentities = parsedIncoming.map {
                TransferLegIdentity(accountID: $0.account.id, currencyCode: $0.currency)
            }

            if TransactionEditService.hasDuplicateTransferLegs(outgoingIdentities) {
                showValidation("相同帳戶及幣種不可重複，請合併金額。")
                return
            }
            if TransactionEditService.hasDuplicateTransferLegs(incomingIdentities) {
                showValidation("相同帳戶及幣種不可重複，請合併金額。")
                return
            }

            var existing = try fetchGroupTransactions(for: originalTransaction)
                .filter { $0.type == .transfer }

            if existing.isEmpty {
                existing = [originalTransaction]
            }

            let groupID = existing.first?.transferGroupID ?? originalTransaction.transferGroupID ?? UUID()
            let now = Date()

            var existingOutgoing = existing.filter { isOutgoing($0) }
            var existingIncoming = existing.filter { !isOutgoing($0) }
            existingOutgoing.sort { $0.createdAt < $1.createdAt }
            existingIncoming.sort { $0.createdAt < $1.createdAt }

            let outgoingCounterpart = counterpartSummary(accounts: parsedIncoming.map { $0.account })
            let incomingCounterpart = counterpartSummary(accounts: parsedOutgoing.map { $0.account })
            let baseNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

            let updatedOutgoing = try synchronizeLegs(
                desired: parsedOutgoing,
                existing: existingOutgoing,
                side: .outgoing,
                groupID: groupID,
                date: date,
                noteSuffix: "轉至 \(outgoingCounterpart)",
                baseNote: baseNote,
                now: now
            )

            let updatedIncoming = try synchronizeLegs(
                desired: parsedIncoming,
                existing: existingIncoming,
                side: .incoming,
                groupID: groupID,
                date: date,
                noteSuffix: "來自 \(incomingCounterpart)",
                baseNote: baseNote,
                now: now
            )

            if updatedOutgoing.count == 1, updatedIncoming.count == 1 {
                let outTx = updatedOutgoing[0]
                let inTx = updatedIncoming[0]
                outTx.linkedTransactionID = inTx.id
                inTx.linkedTransactionID = outTx.id
            } else {
                for tx in updatedOutgoing + updatedIncoming {
                    tx.linkedTransactionID = nil
                }
            }

            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            showValidation(error.localizedDescription)
        }
    }

    private func fetchGroupTransactions(for tx: FinancialTransaction) throws -> [FinancialTransaction] {
        if let groupID = tx.transferGroupID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            let groupItems = try modelContext.fetch(descriptor)
            if !groupItems.isEmpty {
                return groupItems
            }
        }

        if let linkedID = tx.linkedTransactionID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.id == linkedID }
            )
            if let linked = try modelContext.fetch(descriptor).first {
                return [tx, linked]
            }
        }

        return [tx]
    }

    private func isOutgoing(_ tx: FinancialTransaction) -> Bool {
        if let side = tx.transferSide {
            return side == .outgoing
        }
        return tx.amount < 0
    }

    private func makeLeg(from tx: FinancialTransaction) -> TransferLegInput {
        TransferLegInput(
            transaction: tx,
            account: tx.account,
            currency: defaultCurrency(for: tx),
            amountString: decimalString(from: abs(tx.amount))
        )
    }

    private func defaultCurrency(for tx: FinancialTransaction?) -> String {
        if let tx, !tx.currencyCode.isEmpty {
            return tx.currencyCode
        }
        return tx?.account?.currency ?? "HKD"
    }

    private func parseLegs(from legs: [TransferLegInput], sideName: String) throws -> [DesiredLeg] {
        var parsed: [DesiredLeg] = []

        for leg in legs {
            guard let account = leg.account else {
                throw NSError(domain: "EditTransferView", code: 1, userInfo: [NSLocalizedDescriptionKey: "請為每一筆\(sideName)項目選擇帳戶。"])
            }
            guard let amount = positiveDecimal(from: leg.amountString) else {
                throw NSError(domain: "EditTransferView", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(sideName)金額需大於 0。"])
            }

            parsed.append(
                DesiredLeg(
                    account: account,
                    currency: leg.currency,
                    amount: amount
                )
            )
        }

        return parsed
    }

    private func synchronizeLegs(
        desired: [DesiredLeg],
        existing: [FinancialTransaction],
        side: TransferSide,
        groupID: UUID,
        date: Date,
        noteSuffix: String,
        baseNote: String,
        now: Date
    ) throws -> [FinancialTransaction] {
        var updated: [FinancialTransaction] = []

        for index in desired.indices {
            let target = desired[index]
            let tx: FinancialTransaction

            if index < existing.count {
                tx = existing[index]
            } else {
                tx = FinancialTransaction(
                    amount: 0,
                    currencyCode: target.currency,
                    date: date,
                    note: "",
                    type: .transfer
                )
                modelContext.insert(tx)
            }

            tx.type = .transfer
            tx.amount = (side == .outgoing) ? -abs(target.amount) : abs(target.amount)
            tx.currencyCode = target.currency
            tx.account = target.account
            tx.date = date
            tx.transferGroupID = groupID
            tx.transferSide = side
            tx.updatedAt = now
            tx.note = baseNote.isEmpty
                ? "轉帳 (\(noteSuffix))"
                : "\(baseNote) (\(noteSuffix))"

            updated.append(tx)
        }

        if existing.count > desired.count {
            for tx in existing.dropFirst(desired.count) {
                modelContext.delete(tx)
            }
        }

        return updated
    }

    private func counterpartSummary(accounts: [Account]) -> String {
        if accounts.count == 1 {
            return accounts[0].name
        }
        return "\(accounts.count) 個帳戶"
    }

    private func extractMemo(from note: String) -> String {
        let separators = [
            " (轉至", " (來自", " (代墊給", " (還款至", " (借入至", " (還款給"
        ]

        for separator in separators {
            if let range = note.range(of: separator) {
                return String(note[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decimalString(from value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func positiveDecimal(from value: String) -> Decimal? {
        guard let parsed = Decimal(string: value), parsed > 0 else { return nil }
        return parsed
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

    private func showValidation(_ message: String) {
        validationMessage = message
        showingValidationAlert = true
    }
}
