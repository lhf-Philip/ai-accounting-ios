import SwiftUI
import SwiftData
import Charts

struct ChartsView: View {
    @Query(sort: \FinancialTransaction.date) private var transactions: [FinancialTransaction]
    @Query(sort: \CategoryMonthlyBudget.monthKey, order: .reverse) private var budgets: [CategoryMonthlyBudget]
    @StateObject private var currencyService = CurrencyService.shared
    
    @AppStorage(DateFilterPreferenceKeys.filterType) private var filterTypeRaw: String = FilterType.month.rawValue
    @AppStorage(DateFilterPreferenceKeys.selectedDate) private var selectedDateTimeInterval: Double = Date().timeIntervalSince1970
    @AppStorage(DateFilterPreferenceKeys.customStartDate) private var customStartDateTimeInterval: Double = Date().timeIntervalSince1970
    @AppStorage(DateFilterPreferenceKeys.customEndDate) private var customEndDateTimeInterval: Double = Date().timeIntervalSince1970
    @State private var showingFilterSheet = false
    @State private var chartMode: ChartMode = .category
    @State private var flowMode: FlowMode = .expense
    @AppStorage("pinReportsControls") private var pinReportsControls: Bool = true
    
    // 互動狀態
    @State private var selectedTagForDetail: String?
    @State private var selectedReportDetail: ReportDetail?
    
    enum ChartMode: String, CaseIterable {
        case category = "依分類"
        case tag = "依標籤"
    }
    
    enum FlowMode: String, CaseIterable {
        case expense = "支出"
        case income = "收入"
        
        var transactionType: TransactionType {
            switch self {
            case .expense: return .expense
            case .income: return .income
            }
        }
        
        var emptyTitle: String {
            switch self {
            case .expense: return "本期無支出"
            case .income: return "本期無收入"
            }
        }
        
        var totalTitle: String {
            switch self {
            case .expense: return "總支出"
            case .income: return "總收入"
            }
        }
    }
    
    struct ReportDetail: Identifiable {
        let id = UUID()
        let title: String
        let estimatedAmount: Decimal
        let mainCurrency: String
        let originalCurrencySummary: String
        let grossEstimatedAmount: Decimal
        let grossOriginalCurrencySummary: String
        let refundReductionEstimatedAmount: Decimal
        let refundReductionOriginalCurrencySummary: String
        let refundSettlementOnlyEstimatedAmount: Decimal
        let refundSettlementOnlyOriginalCurrencySummary: String
        let estimateFootnote: String?
        let transactions: [FinancialTransaction]

        var hasRefundBreakdown: Bool {
            refundReductionEstimatedAmount != 0 || refundSettlementOnlyEstimatedAmount != 0
        }
    }
    
    var body: some View {
        let renderState = makeRenderState()

        NavigationStack {
            VStack(spacing: 0) {
                if pinReportsControls {
                    reportControls
                }

                ScrollView {
                    if !pinReportsControls {
                        reportControls
                    }

                    if renderState.currentData.isEmpty {
                        ContentUnavailableView(flowMode.emptyTitle, systemImage: "chart.pie", description: Text("試試切換日期或記一筆帳"))
                            .padding(.top, 40)
                    } else if chartMode == .tag && selectedTagForDetail != nil {
                        tagDetailView(renderState: renderState)
                    } else {
                        mainChartView(data: renderState.currentData)
                    }
                }
                
                if !renderState.budgetAlerts.isEmpty && flowMode == .expense {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本月超支提醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(renderState.budgetAlerts.prefix(3)) { status in
                            HStack {
                                Text(status.budget.category?.name ?? "未分類")
                                    .font(.caption)
                                Spacer()
                                Text("超支 \(abs(status.remaining).formatted(.currency(code: status.budget.currencyCode)))")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
            .prominentInlineTitle("報表")
            .sheet(isPresented: $showingFilterSheet) {
                DateFilterView(
                    filterType: filterTypeBinding,
                    selectedDate: selectedDateBinding,
                    customStartDate: customStartDateBinding,
                    customEndDate: customEndDateBinding
                )
            }
            .sheet(item: $selectedReportDetail) { detail in
                ReportTransactionListView(detail: detail)
            }
        }
    }

    private var reportControls: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { showingFilterSheet = true }) {
                    HStack(spacing: 4) {
                        Text(filterDisplayString).font(.headline)
                        Image(systemName: "chevron.down").font(.caption).bold()
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Picker("收支", selection: $flowMode) {
                    ForEach(FlowMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .onChange(of: flowMode) { _, _ in
                    selectedTagForDetail = nil
                }

                Picker("模式", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .onChange(of: chartMode) { _, _ in
                    selectedTagForDetail = nil
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - 主圖表視圖
    func mainChartView(data: [ChartData]) -> some View {
        VStack(spacing: 24) {
            chartView(data: data)
                .frame(height: 300)
                .padding(.horizontal)
            
            LazyVStack(spacing: 16) {
                ForEach(data, id: \.key) { item in
                    Button(action: {
                        if chartMode == .tag {
                            withAnimation { selectedTagForDetail = item.name }
                        } else {
                            presentTransactions(for: item)
                        }
                    }) {
                        rowView(
                            item: item,
                            total: totalAmount(data: data),
                            trailingIcon: chartMode == .tag ? "chevron.right" : "list.bullet"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal).padding(.bottom, 20)
        }
    }
    
    // MARK: - 標籤詳情視圖
    private func tagDetailView(renderState: ChartsRenderState) -> some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: { withAnimation { selectedTagForDetail = nil } }) {
                    HStack {
                        Image(systemName: "arrow.left.circle.fill").font(.title2)
                        Text(selectedTagForDetail ?? "").font(.title3).bold()
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            
            let detailData = renderState.categoryBreakdown(for: selectedTagForDetail)
            
            if detailData.isEmpty {
                ContentUnavailableView("此標籤無分類數據", systemImage: "tag.slash")
            } else {
                chartView(data: detailData)
                    .frame(height: 250)
                    .padding(.horizontal)
                
                LazyVStack(spacing: 16) {
                    ForEach(detailData, id: \.key) { item in
                        Button(action: {
                            presentTransactions(for: item, tagName: selectedTagForDetail)
                        }) {
                            rowView(item: item, total: totalAmount(data: detailData), trailingIcon: "list.bullet")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.bottom, 20)
            }
        }
        .padding(.top)
    }
    
    // MARK: - 通用組件
    func chartView(data: [ChartData]) -> some View {
        let total = totalAmount(data: data)
        return ZStack {
            Chart(data, id: \.key) { item in
                SectorMark(
                    angle: .value("金額", item.amount),
                    innerRadius: .ratio(0.65),
                    outerRadius: .ratio(0.9),
                    angularInset: 2.0
                )
                .cornerRadius(6)
                .foregroundStyle(item.color)
            }
            VStack {
                Text(flowMode.totalTitle).font(.callout).foregroundStyle(.secondary)
                Text(total.formatted(.currency(code: currencyService.mainCurrency)))
                    .font(.title2).bold().foregroundStyle(.primary)
            }
        }
    }
    
    func rowView(item: ChartData, total: Decimal, trailingIcon: String) -> some View {
        let percent = total > 0 ? (item.amount / total * 100) : 0
        let percentDouble = NSDecimalNumber(decimal: percent).doubleValue
        let safeProgressRatio: CGFloat = {
            guard percentDouble.isFinite else { return 0 }
            let normalized = percentDouble / 100.0
            return CGFloat(min(max(normalized, 0), 1))
        }()
        let percentText = "\(percent.formatted(.number.precision(.fractionLength(1))))%"
        let footnoteText = item.estimateFootnote.map { "\(percentText)・\($0)" } ?? percentText
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(item.color).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body).fontWeight(.medium)
                Text(item.originalCurrencySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.1))
                        Capsule()
                            .fill(item.color)
                            .frame(width: max(0, geo.size.width) * safeProgressRatio)
                    }
                }.frame(height: 6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("約 \(item.amount.formatted(.currency(code: currencyService.mainCurrency)))").font(.body).bold()
                HStack(spacing: 4) {
                    Text(footnoteText)
                    Image(systemName: trailingIcon)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Data Logic
    private func makeRenderState() -> ChartsRenderState {
        ChartsRenderState(
            transactions: transactions,
            budgets: budgets,
            currencyService: currencyService,
            filterType: filterType,
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            chartMode: chartMode,
            flowMode: flowMode
        )
    }

    struct ChartData {
        let key: String
        let name: String
        let amount: Decimal
        let color: Color
        let transactions: [FinancialTransaction]
        let originalCurrencySummary: String
        let grossEstimatedAmount: Decimal
        let grossOriginalCurrencySummary: String
        let refundReductionEstimatedAmount: Decimal
        let refundReductionOriginalCurrencySummary: String
        let refundSettlementOnlyEstimatedAmount: Decimal
        let refundSettlementOnlyOriginalCurrencySummary: String
        let estimateFootnote: String?
    }
    
    func presentTransactions(for item: ChartData, tagName: String? = nil) {
        let flowLabel = flowMode == .income ? "收入" : "支出"
        let title: String
        if let tagName {
            title = "\(flowLabel)・\(tagName)・\(item.name)"
        } else {
            title = "\(flowLabel)・\(item.name)"
        }
        
        let sortedTransactions = item.transactions.sorted { $0.date > $1.date }
        selectedReportDetail = ReportDetail(
            title: title,
            estimatedAmount: item.amount,
            mainCurrency: currencyService.mainCurrency,
            originalCurrencySummary: item.originalCurrencySummary,
            grossEstimatedAmount: item.grossEstimatedAmount,
            grossOriginalCurrencySummary: item.grossOriginalCurrencySummary,
            refundReductionEstimatedAmount: item.refundReductionEstimatedAmount,
            refundReductionOriginalCurrencySummary: item.refundReductionOriginalCurrencySummary,
            refundSettlementOnlyEstimatedAmount: item.refundSettlementOnlyEstimatedAmount,
            refundSettlementOnlyOriginalCurrencySummary: item.refundSettlementOnlyOriginalCurrencySummary,
            estimateFootnote: item.estimateFootnote,
            transactions: sortedTransactions
        )
    }
    
    func totalAmount(data: [ChartData]) -> Decimal { data.reduce(0) { $0 + $1.amount } }
    
    var filterDisplayString: String {
        filterType.displayString(
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            allTitle: "全部時間"
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
}

@MainActor
private struct ChartsRenderState {
    let currentData: [ChartsView.ChartData]
    let budgetAlerts: [BudgetStatus]

    private let snapshots: [ReportTransactionSnapshot]
    private let transactionsByID: [UUID: FinancialTransaction]
    private let currencyService: CurrencyService
    private let flow: ReportFlow
    private let startDate: Date?
    private let endDate: Date?

    init(
        transactions: [FinancialTransaction],
        budgets: [CategoryMonthlyBudget],
        currencyService: CurrencyService,
        filterType: FilterType,
        selectedDate: Date,
        customStartDate: Date,
        customEndDate: Date,
        chartMode: ChartsView.ChartMode,
        flowMode: ChartsView.FlowMode
    ) {
        let interval = filterType.dateInterval(
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
        let snapshots = transactions.map(ReportTransactionSnapshot.init)
        let transactionsByID = Dictionary(
            uniqueKeysWithValues: transactions.map { ($0.id, $0) }
        )
        let flow: ReportFlow = flowMode == .expense ? .expense : .income
        let grouping: ReportGroupingMode = chartMode == .category ? .category : .tag
        let aggregation = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: snapshots,
                flow: flow,
                grouping: grouping,
                startDate: interval?.start,
                endDate: interval?.end
            ),
            currencyConverter: currencyService
        )

        self.currentData = Self.chartData(
            from: aggregation.slices,
            transactionsByID: transactionsByID,
            chartMode: chartMode
        )
        self.budgetAlerts = BudgetService.statuses(
            for: BudgetService.monthKey(from: Date()),
            budgets: budgets,
            transactions: transactions,
            currencyService: currencyService
        )
        .filter { $0.ratio >= 1 }
        self.snapshots = snapshots
        self.transactionsByID = transactionsByID
        self.currencyService = currencyService
        self.flow = flow
        self.startDate = interval?.start
        self.endDate = interval?.end
    }

    func categoryBreakdown(for tagName: String?) -> [ChartsView.ChartData] {
        guard let tagName else { return [] }

        let aggregation = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: snapshots,
                flow: flow,
                grouping: .category,
                startDate: startDate,
                endDate: endDate,
                tagFilter: tagName
            ),
            currencyConverter: currencyService
        )
        return Self.chartData(
            from: aggregation.slices,
            transactionsByID: transactionsByID,
            chartMode: .category
        )
    }

    private static func chartData(
        from slices: [ReportSlice],
        transactionsByID: [UUID: FinancialTransaction],
        chartMode: ChartsView.ChartMode
    ) -> [ChartsView.ChartData] {
        slices.enumerated().map { index, slice in
            let detail = slice.detailSummary
            let displayColor: Color
            if let colorHex = slice.categoryColorHex {
                displayColor = Color(hex: colorHex)
            } else if chartMode == .tag {
                displayColor = Color.generateDistinctColor(index: index, total: slices.count)
            } else {
                displayColor = .gray
            }
            return ChartsView.ChartData(
                key: slice.key,
                name: slice.name,
                amount: detail.estimatedAmount,
                color: displayColor,
                transactions: detail.transactionIDs.compactMap { transactionsByID[$0] },
                originalCurrencySummary: reportCurrencySummary(detail.originalCurrencyTotals),
                grossEstimatedAmount: detail.grossEstimatedAmount,
                grossOriginalCurrencySummary: reportCurrencySummary(detail.grossOriginalCurrencyTotals),
                refundReductionEstimatedAmount: detail.refundReductionEstimatedAmount,
                refundReductionOriginalCurrencySummary: reportCurrencySummary(detail.refundReductionOriginalCurrencyTotals),
                refundSettlementOnlyEstimatedAmount: detail.refundSettlementOnlyEstimatedAmount,
                refundSettlementOnlyOriginalCurrencySummary: reportCurrencySummary(detail.refundSettlementOnlyOriginalCurrencyTotals),
                estimateFootnote: detail.estimateStatus.label
            )
        }
    }
}

private extension ReportTransactionSnapshot {
    init(transaction: FinancialTransaction) {
        self.init(
            id: transaction.id,
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            date: transaction.date,
            type: transaction.type,
            categoryID: transaction.category?.id,
            categoryName: transaction.category?.name,
            categoryColorHex: transaction.category?.colorHex,
            tagNames: transaction.tags.map(\.name)
        )
    }
}

private func reportCurrencySummary(_ totals: [ReportCurrencyTotal]) -> String {
    totals
        .map { total in
            total.amount.formatted(.currency(code: total.currencyCode))
        }
        .joined(separator: " · ")
}

private struct ReportTransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var allTransactions: [FinancialTransaction]
    @Query private var advanceCases: [AdvanceCase]
    @Query private var advanceParticipants: [AdvanceParticipant]
    @Query private var advanceRepayments: [AdvanceRepayment]

    let detail: ChartsView.ReportDetail

    @State private var transactionToEdit: FinancialTransaction?
    @State private var deletionErrorMessage: String?

    var body: some View {
        let renderState = ReportTransactionListRenderState(
            transactions: detail.transactions,
            allTransactions: allTransactions,
            advanceParticipants: advanceParticipants,
            advanceRepayments: advanceRepayments
        )

        NavigationStack {
            Group {
                if detail.transactions.isEmpty {
                    ContentUnavailableView("找不到交易", systemImage: "tray")
                } else {
                    List {
                        Section {
                            ReportDetailSummaryCard(detail: detail)
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .listRowBackground(Color.clear)
                        }

                        ForEach(renderState.groupedTransactions, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.items) { tx in
                                    TransactionRow(
                                        transaction: tx,
                                        transferCounterpart: renderState.transferCounterpartByID[tx.id]
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        transactionToEdit = tx
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            deleteTransaction(tx)
                                        } label: {
                                            Label("刪除", systemImage: "trash")
                                        }

                                        Button {
                                            transactionToEdit = tx
                                        } label: {
                                            Label("編輯", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
        }
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
    private func transactionEditor(for tx: FinancialTransaction, renderState: ReportTransactionListRenderState) -> some View {
        let group = TransferEditRoutingService.groupTransactions(for: tx, in: renderState.allTransactions)
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

    private func deleteTransaction(_ tx: FinancialTransaction) {
        do {
            try LedgerDeletionService.delete(transaction: tx, modelContext: modelContext)
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

}

private struct ReportDetailSummaryCard: View {
    let detail: ChartsView.ReportDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("明細總額")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("約 \(detail.estimatedAmount.formatted(.currency(code: detail.mainCurrency)))")
                        .font(.title3.weight(.bold))
                }

                Spacer()

                Text("\(detail.transactions.count) 筆")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.blue)
                    .background(Color.blue.opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("原幣種合計")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(detail.originalCurrencySummary.isEmpty ? "沒有金額資料" : detail.originalCurrencySummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if detail.hasRefundBreakdown {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("退款扣減")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ReportBreakdownRow(
                        title: "總支出",
                        amount: detail.grossEstimatedAmount,
                        mainCurrency: detail.mainCurrency,
                        originalSummary: detail.grossOriginalCurrencySummary
                    )
                    ReportBreakdownRow(
                        title: "退款扣減",
                        amount: detail.refundReductionEstimatedAmount,
                        mainCurrency: detail.mainCurrency,
                        originalSummary: detail.refundReductionOriginalCurrencySummary
                    )

                    if detail.refundSettlementOnlyEstimatedAmount != 0 {
                        ReportBreakdownRow(
                            title: "只作結算",
                            amount: detail.refundSettlementOnlyEstimatedAmount,
                            mainCurrency: detail.mainCurrency,
                            originalSummary: detail.refundSettlementOnlyOriginalCurrencySummary
                        )
                    }
                }
            }

            if let estimateFootnote = detail.estimateFootnote {
                Label(estimateFootnote, systemImage: estimateFootnote == "估算不完整" ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(estimateFootnote == "估算不完整" ? .orange : .secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ReportBreakdownRow: View {
    let title: String
    let amount: Decimal
    let mainCurrency: String
    let originalSummary: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                if !originalSummary.isEmpty {
                    Text(originalSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(amount.formatted(.currency(code: mainCurrency)))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct ReportTransactionListRenderState {
    let allTransactions: [FinancialTransaction]
    let transferCounterpartByID: [UUID: TransferCounterpartInfo]
    let groupedTransactions: [(title: String, items: [FinancialTransaction])]
    let initialAdvanceGroupIDs: Set<UUID>
    let repaymentAdvanceGroupIDs: Set<UUID>

    init(
        transactions: [FinancialTransaction],
        allTransactions: [FinancialTransaction],
        advanceParticipants: [AdvanceParticipant],
        advanceRepayments: [AdvanceRepayment]
    ) {
        self.allTransactions = allTransactions
        self.initialAdvanceGroupIDs = Set(advanceParticipants.compactMap(\.initialTransferGroupID))
        self.repaymentAdvanceGroupIDs = Set(advanceRepayments.compactMap(\.linkedTransferGroupID))
        self.transferCounterpartByID = TransferPresentationService.counterpartMap(transactions: allTransactions)
        self.groupedTransactions = Self.groupedTransactions(from: transactions)
    }

    private static func groupedTransactions(
        from transactions: [FinancialTransaction]
    ) -> [(title: String, items: [FinancialTransaction])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd (E)"
        let grouped = Dictionary(grouping: transactions) { tx in
            formatter.string(from: tx.date)
        }
        return grouped
            .sorted { lhs, rhs in
                guard let leftDate = lhs.value.first?.date, let rightDate = rhs.value.first?.date else {
                    return lhs.key > rhs.key
                }
                return leftDate > rightDate
            }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }
}

extension Color {
    static func generateDistinctColor(index: Int, total: Int) -> Color {
        let goldenRatio = 0.618033988749895
        let hue = Double(index) * goldenRatio
        let hueRes = hue.truncatingRemainder(dividingBy: 1.0)
        return Color(hue: hueRes, saturation: 0.75, brightness: 0.95)
    }
}
