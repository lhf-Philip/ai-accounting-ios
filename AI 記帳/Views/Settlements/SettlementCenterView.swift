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

struct SettlementCenterView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \AdvanceCase.date, order: .reverse) private var advanceCases: [AdvanceCase]
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @StateObject private var currencyService = CurrencyService.shared
    @AppStorage("mainCurrency") private var mainCurrency: String = "HKD"
    @State private var mode: SettlementCenterMode = .people
    @State private var selectedPerson: SettlementPersonSummary?
    @State private var timelineFilter: SettlementTimelineFilter?
    @State private var debtRoute: SettlementDebtRoute?

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

        items += advanceCases.flatMap(\.repayments).map { repayment in
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
        .confirmationDialog("結算動作", isPresented: Binding(
            get: { selectedPerson != nil },
            set: { if !$0 { selectedPerson = nil } }
        ), titleVisibility: .visible) {
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
                Text("\(summary.name)：\(directionText(for: summary.netBalanceInMainCurrency))")
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
        var totals: [String: Decimal] = [:]
        if account.baseBalance != 0 {
            totals[account.currency, default: 0] += account.baseBalance
        }
        for transaction in transactions where transaction.account?.id == account.id {
            totals[transaction.currencyCode, default: 0] += transaction.amount
        }
        return totals
            .filter { $0.value != 0 }
            .sorted { $0.key < $1.key }
            .map { SettlementCurrencyBalance(currencyCode: $0.key, amount: $0.value) }
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
}
