import SwiftUI
import SwiftData

private enum SettlementCenterMode: String, CaseIterable, Identifiable {
    case people = "按對象"
    case cases = "按案件"
    case timeline = "時間線"

    var id: String { rawValue }
}

private struct SettlementPersonSummary: Identifiable {
    let id: UUID
    let account: Account
    let name: String
    let balances: [SettlementCurrencyBalance]
    let offsetCandidates: [AdvanceService.MutualDebtOffsetCandidate]
    let netBalanceInMainCurrency: Decimal
    let advanceCaseCount: Int
    let repaymentCount: Int
    let forgivenessCount: Int
    let latestActivityDate: Date?
}

private struct SettlementCurrencyBalance: Identifiable {
    let currencyCode: String
    let amount: Decimal

    var id: String { currencyCode }
}

private struct SettlementTimelineItem: Identifiable {
    let id: String
    let relatedAccountID: UUID?
    let date: Date
    let title: String
    let subtitle: String
    let amount: Decimal?
    let currencyCode: String
    let tint: Color
}

private struct SettlementTimelineFilter: Identifiable {
    let accountID: UUID
    let name: String

    var id: UUID { accountID }
}

private struct SettlementDebtRoute: Identifiable, Hashable {
    let accountID: UUID
    let mode: AddDebtView.DebtMode
    let forgivenessDirection: DebtForgivenessDirection?
    let note: String

    var id: String {
        "\(accountID.uuidString)-\(mode.rawValue)-\(forgivenessDirection?.rawValue ?? "none")-\(note)"
    }
}

private struct ManualDebtSettlementDraft: Identifiable {
    let id = UUID()
    let account: Account
    let currencyCode: String
    let direction: AdvanceService.ManualDebtSettlementDirection
    let suggestedAmount: Decimal
    let maximumAmount: Decimal
    let visibleBalance: Decimal

    var directionTitle: String {
        switch direction {
        case .receivable:
            "結清對方欠你的 \(currencyCode)"
        case .payable:
            "結清你欠對方的 \(currencyCode)"
        }
    }
}

struct SettlementCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \AdvanceCase.date, order: .reverse) private var advanceCases: [AdvanceCase]
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @StateObject private var currencyService = CurrencyService.shared
    @AppStorage("mainCurrency") private var mainCurrency: String = "HKD"
    @State private var mode: SettlementCenterMode = .people
    @State private var selectedPerson: SettlementPersonSummary?
    @State private var timelineFilter: SettlementTimelineFilter?
    @State private var debtRoute: SettlementDebtRoute?
    @State private var manualDebtSettlementDraft: ManualDebtSettlementDraft?
    @State private var statusMessage: String?

    private var activeDebtAccounts: [Account] {
        accounts.filter { $0.type == .debt && !$0.isArchived }
    }

    private var personSummaries: [SettlementPersonSummary] {
        activeDebtAccounts.map { account in
            let participants = advanceCases.flatMap(\.participants).filter { $0.debtAccount?.id == account.id }
            let repayments = advanceCases.flatMap(\.repayments).filter { $0.participant?.debtAccount?.id == account.id }
            let forgiveness = transactions.filter {
                $0.account?.id == account.id && TransactionSemantics.isDebtForgiveness(note: $0.note)
            }
            let offsetCandidates = Set(participants.compactMap { $0.advanceCase?.currencyCode })
                .compactMap {
                    AdvanceService.mutualDebtOffsetCandidate(
                        debtAccount: account,
                        currencyCode: $0,
                        advanceCases: advanceCases,
                        modelContext: modelContext
                    )
                }
                .sorted { $0.currencyCode < $1.currencyCode }
            let caseCount = Set(participants.compactMap { $0.advanceCase?.id }).count
            let balances = balances(for: account)
            let netInMainCurrency = balances.reduce(Decimal.zero) { partial, balance in
                partial + currencyService.convert(
                    amount: balance.amount,
                    from: balance.currencyCode,
                    to: mainCurrency
                )
            }

            return SettlementPersonSummary(
                id: account.id,
                account: account,
                name: account.name,
                balances: balances,
                offsetCandidates: offsetCandidates,
                netBalanceInMainCurrency: netInMainCurrency,
                advanceCaseCount: caseCount,
                repaymentCount: repayments.count,
                forgivenessCount: forgiveness.count,
                latestActivityDate: latestActivityDate(for: account)
            )
        }
        .filter { !$0.balances.isEmpty || $0.advanceCaseCount > 0 || $0.repaymentCount > 0 || $0.forgivenessCount > 0 }
        .sorted { abs($0.netBalanceInMainCurrency) > abs($1.netBalanceInMainCurrency) }
    }

    private var activeCaseSummaries: [AdvanceCase] {
        advanceCases.sorted {
            let lhsOutstanding = AdvanceService.outstandingAmount(for: $0)
            let rhsOutstanding = AdvanceService.outstandingAmount(for: $1)
            if lhsOutstanding == rhsOutstanding {
                return $0.date > $1.date
            }
            return lhsOutstanding > rhsOutstanding
        }
    }

    private var timelineItems: [SettlementTimelineItem] {
        let advanceInitialGroupIDs = Set(advanceCases.flatMap(\.participants).compactMap(\.initialTransferGroupID))
        let repaymentGroupIDs = Set(advanceCases.flatMap(\.repayments).compactMap(\.linkedTransferGroupID))
        let advanceGroupIDs = advanceInitialGroupIDs.union(repaymentGroupIDs)

        var items: [SettlementTimelineItem] = advanceCases.map { advanceCase in
            SettlementTimelineItem(
                id: "case-\(advanceCase.id.uuidString)",
                relatedAccountID: nil,
                date: advanceCase.date,
                title: "建立代墊：\(advanceCase.title)",
                subtitle: "\(advanceCase.participants.count) 位對象，未清 \(AdvanceService.outstandingAmount(for: advanceCase).formatted(.currency(code: advanceCase.currencyCode)))",
                amount: AdvanceService.totalAdvanced(for: advanceCase),
                currencyCode: advanceCase.currencyCode,
                tint: .orange
            )
        }

        let allRepayments = advanceCases.flatMap(\.repayments)
        items += allRepayments.filter {
            !AdvanceService.isMutualDebtOffset(note: $0.note)
                && !AdvanceService.isManualDebtSettlement(note: $0.note)
        }.map { repayment in
            SettlementTimelineItem(
                id: "repayment-\(repayment.id.uuidString)",
                relatedAccountID: repayment.participant?.debtAccount?.id,
                date: repayment.date,
                title: "代墊還款：\(repayment.participant?.name ?? "未命名對象")",
                subtitle: repayment.advanceCase?.title ?? "未連結代墊單",
                amount: repayment.amount,
                currencyCode: repayment.currencyCode,
                tint: .green
            )
        }

        let manualRepaymentsByID = Dictionary(grouping: allRepayments.compactMap { repayment -> (UUID, AdvanceRepayment)? in
            guard let settlementID = AdvanceService.manualDebtSettlementID(from: repayment.note) else { return nil }
            return (settlementID, repayment)
        }) { $0.0 }
        items += manualRepaymentsByID.compactMap { settlementID, entries in
            let repayments = entries.map(\.1)
            guard let first = repayments.first else { return nil }
            let total = repayments.reduce(Decimal.zero) { $0 + $1.normalizedAmount }
            return SettlementTimelineItem(
                id: "manual-settlement-\(settlementID.uuidString)",
                relatedAccountID: first.participant?.debtAccount?.id,
                date: first.date,
                title: "跨幣種平賬",
                subtitle: first.participant?.debtAccount?.name ?? "手動結清代墊餘額",
                amount: total,
                currencyCode: first.currencyCode,
                tint: .indigo
            )
        }

        let offsetRepaymentsByID = Dictionary(grouping: allRepayments.compactMap { repayment -> (UUID, AdvanceRepayment)? in
            guard let offsetID = AdvanceService.mutualDebtOffsetID(from: repayment.note) else { return nil }
            return (offsetID, repayment)
        }) { $0.0 }
        items += offsetRepaymentsByID.compactMap { offsetID, entries in
            let repayments = entries.map(\.1)
            guard let first = repayments.first else { return nil }
            let total = repayments.reduce(Decimal.zero) { $0 + $1.amount } / 2
            return SettlementTimelineItem(
                id: "offset-\(offsetID.uuidString)",
                relatedAccountID: first.participant?.debtAccount?.id,
                date: first.date,
                title: "債務抵銷",
                subtitle: first.participant?.debtAccount?.name ?? "互相代墊抵銷",
                amount: total,
                currencyCode: first.currencyCode,
                tint: .teal
            )
        }

        items += transactions.compactMap { transaction in
            guard transaction.account?.type == .debt, transaction.type == .transfer else { return nil }
            let isForgiveness = TransactionSemantics.isDebtForgiveness(note: transaction.note)
            if !isForgiveness, let groupID = transaction.transferGroupID, advanceGroupIDs.contains(groupID) {
                return nil
            }

            let title: String
            let tint: Color
            if isForgiveness {
                title = TransactionSemantics.debtForgivenessDisplayTitle(note: transaction.note)
                tint = .purple
            } else if transaction.amount < 0 {
                title = "債務增加"
                tint = .red
            } else {
                title = "債務減少"
                tint = .blue
            }

            return SettlementTimelineItem(
                id: "debt-\(transaction.id.uuidString)",
                relatedAccountID: transaction.account?.id,
                date: transaction.date,
                title: debtTimelineTitle(for: transaction, fallback: title),
                subtitle: transaction.account?.name ?? "借貸帳戶",
                amount: transaction.amount,
                currencyCode: transaction.currencyCode,
                tint: tint
            )
        }

        return items.sorted { $0.date > $1.date }
    }

    private var displayedTimelineItems: [SettlementTimelineItem] {
        guard let timelineFilter else { return timelineItems }
        return timelineItems.filter { $0.relatedAccountID == timelineFilter.accountID }
    }

    private var totalNetInMainCurrency: Decimal {
        personSummaries.reduce(Decimal.zero) { $0 + $1.netBalanceInMainCurrency }
    }

    private var settlementSummaryText: String {
        var lines: [String] = [
            "結算中心摘要",
            "淨額：\(totalNetInMainCurrency.formatted(.currency(code: mainCurrency)))",
            ""
        ]
        lines += personSummaries.map { summary in
            let primaryBalance = summary.balances.first
            let balanceText = primaryBalance.map {
                $0.amount.formatted(.currency(code: $0.currencyCode))
            } ?? Decimal.zero.formatted(.currency(code: mainCurrency))
            return "\(summary.name), \(directionText(for: summary.netBalanceInMainCurrency)), \(balanceText), 代墊案件 \(summary.advanceCaseCount), 還款 \(summary.repaymentCount), 免除 \(summary.forgivenessCount)"
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("整體淨額 (\(mainCurrency))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(totalNetInMainCurrency.formatted(.currency(code: mainCurrency)))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(totalNetInMainCurrency >= 0 ? .green : .red)
                    Text("正數代表你待收；負數代表你待還。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                Picker("視角", selection: $mode) {
                    ForEach(SettlementCenterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch mode {
            case .people:
                peopleSection
            case .cases:
                casesSection
            case .timeline:
                timelineSection
            }

            Section("快速動作") {
                NavigationLink(destination: AdvancesView()) {
                    Label("前往代墊追蹤", systemImage: "person.2.fill")
                }
                NavigationLink(destination: AddDebtView()) {
                    Label("新增借貸 / 還款 / 免除債務", systemImage: "arrow.left.arrow.right")
                }
            }
        }
        .prominentInlineTitle("結算中心")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: settlementSummaryText) {
                    Label("分享摘要", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task {
            await currencyService.fetchRates()
        }
        .alert("結算中心", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
        .confirmationDialog("結算動作", isPresented: Binding(
            get: { selectedPerson != nil },
            set: { if !$0 { selectedPerson = nil } }
        ), titleVisibility: .visible) {
            if let summary = selectedPerson {
                ForEach(summary.offsetCandidates) { candidate in
                    Button("抵銷 \(candidate.amount.formatted(.currency(code: candidate.currencyCode)))") {
                        recordOffset(candidate)
                    }
                }
                ForEach(manualSettlementDrafts(for: summary)) { draft in
                    Button("\(draft.directionTitle) \(draft.suggestedAmount.formatted(.currency(code: draft.currencyCode)))") {
                        selectedPerson = nil
                        manualDebtSettlementDraft = draft
                    }
                }
            }
            if let summary = selectedPerson, summary.netBalanceInMainCurrency > 0 {
                Button("記錄對方還款") {
                    selectedPerson = nil
                    debtRoute = SettlementDebtRoute(
                        accountID: summary.id,
                        mode: .borrow,
                        forgivenessDirection: nil,
                        note: "對方還款"
                    )
                }
                Button("免除對方欠款", role: .destructive) {
                    selectedPerson = nil
                    debtRoute = SettlementDebtRoute(
                        accountID: summary.id,
                        mode: .forgive,
                        forgivenessDirection: .forgiveOthers,
                        note: "免除對方欠款"
                    )
                }
            } else if let summary = selectedPerson, summary.netBalanceInMainCurrency < 0 {
                Button("記錄你還款") {
                    selectedPerson = nil
                    debtRoute = SettlementDebtRoute(
                        accountID: summary.id,
                        mode: .repay,
                        forgivenessDirection: nil,
                        note: "你還款"
                    )
                }
                Button("記錄對方免除", role: .destructive) {
                    selectedPerson = nil
                    debtRoute = SettlementDebtRoute(
                        accountID: summary.id,
                        mode: .forgive,
                        forgivenessDirection: .forgivenByOthers,
                        note: "對方免除"
                    )
                }
            }
            Button("查看相關時間線") {
                if let summary = selectedPerson {
                    timelineFilter = SettlementTimelineFilter(accountID: summary.id, name: summary.name)
                    mode = .timeline
                    selectedPerson = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let summary = selectedPerson {
                let offsetText = summary.offsetCandidates.first.map {
                    "\n可抵銷：\($0.amount.formatted(.currency(code: $0.currencyCode)))"
                } ?? ""
                Text("\(summary.name)：\(directionText(for: summary.netBalanceInMainCurrency))\(offsetText)")
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { debtRoute != nil },
            set: { if !$0 { debtRoute = nil } }
        )) {
            if let route = debtRoute,
               let account = accounts.first(where: { $0.id == route.accountID }) {
                AddDebtView(
                    presetDebtAccount: account,
                    presetMode: route.mode,
                    presetForgivenessDirection: route.forgivenessDirection,
                    presetNote: route.note
                )
            } else {
                ContentUnavailableView("找不到對象", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }
        .sheet(item: $manualDebtSettlementDraft) { draft in
            ManualDebtSettlementSheet(draft: draft) { amount, note in
                recordManualDebtSettlement(draft, amount: amount, note: note)
            }
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        if personSummaries.isEmpty {
            Section {
                ContentUnavailableView(
                    "沒有待結算對象",
                    systemImage: "checkmark.circle",
                    description: Text("代墊、借貸、還款和免除債務都清空後，這裡會保持空白。")
                )
            }
        } else {
            Section("按對象") {
                ForEach(personSummaries) { summary in
                    Button {
                        selectedPerson = summary
                    } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.name)
                                    .font(.headline)
                                Text(directionText(for: summary.netBalanceInMainCurrency))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                if let primaryBalance = summary.balances.first {
                                    Text(primaryBalance.amount.formatted(.currency(code: primaryBalance.currencyCode)))
                                        .font(.headline)
                                        .foregroundStyle(primaryBalance.amount >= 0 ? .green : .red)
                                }
                                Text(summary.netBalanceInMainCurrency.formatted(.currency(code: mainCurrency)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            settlementPill("代墊 \(summary.advanceCaseCount)")
                            settlementPill("還款 \(summary.repaymentCount)")
                            settlementPill("免除 \(summary.forgivenessCount)")
                            if let offset = summary.offsetCandidates.first {
                                settlementPill("可抵銷 \(offset.amount.formatted(.currency(code: offset.currencyCode)))")
                            }
                        }

                        if let latest = summary.latestActivityDate {
                            Text("最近：\(latest.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(summary.balances.dropFirst()) { balance in
                            Text("\(balance.currencyCode): \(balance.amount.formatted(.currency(code: balance.currencyCode)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var casesSection: some View {
        if activeCaseSummaries.isEmpty {
            Section {
                ContentUnavailableView(
                    "沒有代墊案件",
                    systemImage: "tray",
                    description: Text("新增代墊後，案件級結算會出現在這裡。")
                )
            }
        } else {
            Section("按案件") {
                ForEach(activeCaseSummaries) { advanceCase in
                    NavigationLink(destination: AdvanceCaseDetailView(advanceCase: advanceCase)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(advanceCase.title)
                                    .font(.headline)
                                Spacer()
                                Text(AdvanceService.outstandingAmount(for: advanceCase).formatted(.currency(code: advanceCase.currencyCode)))
                                    .font(.headline)
                                    .foregroundStyle(AdvanceService.outstandingAmount(for: advanceCase) > 0 ? .orange : .secondary)
                            }
                            Text("\(advanceCase.participants.count) 位對象，總額 \(AdvanceService.totalAdvanced(for: advanceCase).formatted(.currency(code: advanceCase.currencyCode)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(caseProgressText(for: advanceCase))
                                .font(.caption)
                                .foregroundStyle(AdvanceService.outstandingAmount(for: advanceCase) > 0 ? .orange : .secondary)
                            if let top = topOutstandingParticipant(for: advanceCase) {
                                Text("主要未清：\(top.name) \(max(top.owedAmount - top.repaidAmount, 0).formatted(.currency(code: advanceCase.currencyCode)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(advanceCase.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        if displayedTimelineItems.isEmpty {
            Section {
                ContentUnavailableView(
                    "沒有結算時間線",
                    systemImage: "clock",
                    description: Text("代墊、還款、借貸與免除債務紀錄會按時間排列。")
                )
            }
        } else {
            Section(timelineFilter.map { "\($0.name) 的時間線" } ?? "時間線") {
                if timelineFilter != nil {
                    Button("顯示全部時間線") {
                        timelineFilter = nil
                    }
                    .font(.caption)
                }
                ForEach(displayedTimelineItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(item.tint)
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let amount = item.amount {
                            Text(amount.formatted(.currency(code: item.currencyCode)))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(amount >= 0 ? .green : .red)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func directionText(for amount: Decimal) -> String {
        if amount > 0 { return "對方欠你" }
        if amount < 0 { return "你欠對方" }
        return "已結清"
    }

    private func balances(for account: Account) -> [SettlementCurrencyBalance] {
        DebtSettlementBalanceService.balances(
            for: account,
            transactions: transactions,
            advanceCases: advanceCases,
            modelContext: modelContext
        )
        .map { SettlementCurrencyBalance(currencyCode: $0.currencyCode, amount: $0.amount) }
    }

    private func latestActivityDate(for account: Account) -> Date? {
        let transactionDates = transactions
            .filter { $0.account?.id == account.id }
            .map(\.date)
        let repaymentDates = advanceCases
            .flatMap(\.repayments)
            .filter { $0.participant?.debtAccount?.id == account.id }
            .map(\.date)
        let caseDates = advanceCases
            .filter { advanceCase in advanceCase.participants.contains { $0.debtAccount?.id == account.id } }
            .map(\.date)
        return (transactionDates + repaymentDates + caseDates).max()
    }

    private func caseProgressText(for advanceCase: AdvanceCase) -> String {
        let total = AdvanceService.totalAdvanced(for: advanceCase)
        let outstanding = AdvanceService.outstandingAmount(for: advanceCase)
        guard total > 0 else { return "未清比例 0%" }
        let percent = NSDecimalNumber(decimal: outstanding / total * 100).doubleValue
        return String(format: "未清比例 %.0f%%", percent)
    }

    private func topOutstandingParticipant(for advanceCase: AdvanceCase) -> AdvanceParticipant? {
        advanceCase.participants.max {
            max($0.owedAmount - $0.repaidAmount, 0) < max($1.owedAmount - $1.repaidAmount, 0)
        }
    }

    private func manualSettlementDrafts(for summary: SettlementPersonSummary) -> [ManualDebtSettlementDraft] {
        summary.balances.compactMap { balance in
            let visibleAmount = abs(balance.amount)
            guard visibleAmount > 0 else { return nil }
            let direction: AdvanceService.ManualDebtSettlementDirection = balance.amount > 0 ? .receivable : .payable
            let maximum = manualSettlementAvailableAmount(
                for: summary.account,
                currencyCode: balance.currencyCode,
                direction: direction
            )
            guard maximum > 0 else { return nil }
            return ManualDebtSettlementDraft(
                account: summary.account,
                currencyCode: balance.currencyCode,
                direction: direction,
                suggestedAmount: min(visibleAmount, maximum),
                maximumAmount: maximum,
                visibleBalance: balance.amount
            )
        }
    }

    private func manualSettlementAvailableAmount(
        for account: Account,
        currencyCode: String,
        direction: AdvanceService.ManualDebtSettlementDirection
    ) -> Decimal {
        advanceCases
            .filter { $0.currencyCode == currencyCode }
            .flatMap { advanceCase -> [Decimal] in
                let isPayableCase = advanceCase.payerAccount == nil
                switch (direction, isPayableCase) {
                case (.receivable, false), (.payable, true):
                    return advanceCase.participants
                        .filter { $0.debtAccount?.id == account.id }
                        .map(\.remainingAmount)
                default:
                    return []
                }
            }
            .reduce(Decimal.zero, +)
    }

    private func debtTimelineTitle(for transaction: FinancialTransaction, fallback: String) -> String {
        let note = transaction.note
        if TransactionSemantics.isDebtForgiveness(note: note) {
            return fallback
        }
        if note.contains("對方還款") { return "對方還款" }
        if note.contains("你還款") || note.contains("還款給") { return "你還款" }
        if note.contains("借入至") { return "你借入" }
        if note.contains("借出") { return "你借出" }
        return transaction.amount < 0 ? "你借入 / 對方還款" : "你還款 / 你借出"
    }

    private func settlementPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }

    private func recordOffset(_ candidate: AdvanceService.MutualDebtOffsetCandidate) {
        do {
            let result = try AdvanceService.recordMutualDebtOffset(
                debtAccount: candidate.debtAccount,
                currencyCode: candidate.currencyCode,
                modelContext: modelContext
            )
            selectedPerson = nil
            statusMessage = "已抵銷 \(result.amount.formatted(.currency(code: result.currencyCode)))。"
        } catch {
            selectedPerson = nil
            statusMessage = error.localizedDescription
        }
    }

    private func recordManualDebtSettlement(_ draft: ManualDebtSettlementDraft, amount: Decimal, note: String) {
        do {
            let result = try AdvanceService.recordManualDebtSettlement(
                debtAccount: draft.account,
                currencyCode: draft.currencyCode,
                direction: draft.direction,
                amount: amount,
                note: note,
                modelContext: modelContext
            )
            manualDebtSettlementDraft = nil
            statusMessage = "已跨幣種平賬 \(result.amount.formatted(.currency(code: result.currencyCode)))。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct ManualDebtSettlementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: ManualDebtSettlementDraft
    let onConfirm: (Decimal, String) -> Void
    @State private var amountString: String
    @State private var note: String
    @State private var errorMessage: String?

    init(draft: ManualDebtSettlementDraft, onConfirm: @escaping (Decimal, String) -> Void) {
        self.draft = draft
        self.onConfirm = onConfirm
        _amountString = State(initialValue: NSDecimalNumber(decimal: draft.suggestedAmount).stringValue)
        _note = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("對象", value: draft.account.name)
                    LabeledContent("幣種", value: draft.currencyCode)
                    LabeledContent("結算方向", value: draft.directionTitle)
                    LabeledContent("目前顯示淨額", value: draft.visibleBalance.formatted(.currency(code: draft.currencyCode)))
                    LabeledContent("最多可結清", value: draft.maximumAmount.formatted(.currency(code: draft.currencyCode)))
                } footer: {
                    Text("這是手動平賬：不會建立現金或銀行交易，也不會計入收入/支出，只會在代墊紀錄中留下審計紀錄。")
                }

                Section("平賬金額") {
                    TextField("金額", text: $amountString)
                        .keyboardType(.decimalPad)
                    TextField("備註（可選）", text: $note, axis: .vertical)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("跨幣種平賬")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        confirm()
                    }
                }
            }
        }
    }

    private func confirm() {
        guard let amount = Decimal(string: amountString), amount > 0 else {
            errorMessage = "請輸入有效金額。"
            return
        }
        guard amount <= draft.maximumAmount else {
            errorMessage = "平賬金額不能超過可結清金額。"
            return
        }
        onConfirm(amount, note)
        dismiss()
    }
}
