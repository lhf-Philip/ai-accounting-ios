import SwiftUI
import SwiftData
import Charts

struct ChartsView: View {
    @Query(sort: \FinancialTransaction.date) private var transactions: [FinancialTransaction]
    @Query(sort: \CategoryMonthlyBudget.monthKey, order: .reverse) private var budgets: [CategoryMonthlyBudget]
    @StateObject private var currencyService = CurrencyService.shared
    
    @State private var filterType: FilterType = .month
    @State private var selectedDate: Date = Date()
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
        let transactions: [FinancialTransaction]
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
                DateFilterView(filterType: $filterType, selectedDate: $selectedDate)
            }
            .sheet(item: $selectedReportDetail) { detail in
                ReportTransactionListView(title: detail.title, transactions: detail.transactions)
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
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(item.color).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body).fontWeight(.medium)
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
                Text(item.amount.formatted(.currency(code: currencyService.mainCurrency))).font(.body).bold()
                HStack(spacing: 4) {
                    Text("\(percent.formatted(.number.precision(.fractionLength(1))))%")
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
        selectedReportDetail = ReportDetail(title: title, transactions: sortedTransactions)
    }
    
    func totalAmount(data: [ChartData]) -> Decimal { data.reduce(0) { $0 + $1.amount } }
    
    var filterDisplayString: String {
        switch filterType {
        case .all: return "全部時間"
        case .year: return "\(Calendar.current.component(.year, from: selectedDate))年"
        case .month:
            let f = DateFormatter(); f.dateFormat = "yyyy年 M月"; return f.string(from: selectedDate)
        case .day:
            let f = DateFormatter(); f.dateFormat = "M月d日"; return f.string(from: selectedDate)
        }
    }
}

private struct ChartsRenderState {
    let filteredTransactions: [FinancialTransaction]
    let currentData: [ChartsView.ChartData]
    let budgetAlerts: [BudgetStatus]

    private let currencyService: CurrencyService

    init(
        transactions: [FinancialTransaction],
        budgets: [CategoryMonthlyBudget],
        currencyService: CurrencyService,
        filterType: FilterType,
        selectedDate: Date,
        chartMode: ChartsView.ChartMode,
        flowMode: ChartsView.FlowMode
    ) {
        let filteredTransactions = Self.filteredTransactions(
            from: transactions,
            filterType: filterType,
            selectedDate: selectedDate,
            flowMode: flowMode
        )

        self.filteredTransactions = filteredTransactions
        self.currentData = Self.currentData(
            from: filteredTransactions,
            chartMode: chartMode,
            currencyService: currencyService
        )
        self.budgetAlerts = BudgetService.statuses(
            for: BudgetService.monthKey(from: Date()),
            budgets: budgets,
            transactions: transactions,
            currencyService: currencyService
        )
        .filter { $0.ratio >= 1 }
        self.currencyService = currencyService
    }

    func categoryBreakdown(for tagName: String?) -> [ChartsView.ChartData] {
        guard let tagName else { return [] }

        let tagTransactions = filteredTransactions.filter { tx in
            if tagName == "無標籤" { return tx.tags.isEmpty }
            return tx.tags.contains { $0.name == tagName }
        }
        return Self.categoryBreakdown(
            from: tagTransactions,
            currencyService: currencyService
        )
    }

    private static func filteredTransactions(
        from transactions: [FinancialTransaction],
        filterType: FilterType,
        selectedDate: Date,
        flowMode: ChartsView.FlowMode
    ) -> [FinancialTransaction] {
        let calendar = Calendar.current
        return transactions.filter { tx in
            if tx.type != flowMode.transactionType { return false }
            switch filterType {
            case .all: return true
            case .year: return calendar.isDate(tx.date, equalTo: selectedDate, toGranularity: .year)
            case .month: return calendar.isDate(tx.date, equalTo: selectedDate, toGranularity: .month)
            case .day: return calendar.isDate(tx.date, equalTo: selectedDate, toGranularity: .day)
            }
        }
    }

    private static func currentData(
        from transactions: [FinancialTransaction],
        chartMode: ChartsView.ChartMode,
        currencyService: CurrencyService
    ) -> [ChartsView.ChartData] {
        switch chartMode {
        case .category:
            return categoryBreakdown(from: transactions, currencyService: currencyService)
        case .tag:
            return tagBreakdown(from: transactions, currencyService: currencyService)
        }
    }

    private static func categoryBreakdown(
        from transactions: [FinancialTransaction],
        currencyService: CurrencyService
    ) -> [ChartsView.ChartData] {
        let grouped = Dictionary(grouping: transactions) { $0.category?.id.uuidString ?? "uncategorized" }
        let sorted = grouped.sorted {
            let sum0 = $0.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
            let sum1 = $1.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
            return sum0 > sum1
        }
        return sorted.map { item in
            let total = item.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
            let category = item.value.compactMap { $0.category }.first
            let displayColor = category.map { Color(hex: $0.colorHex) } ?? .gray
            return ChartsView.ChartData(
                key: item.key,
                name: category?.name ?? "未分類",
                amount: total,
                color: displayColor,
                transactions: item.value
            )
        }
    }

    private static func tagBreakdown(
        from transactions: [FinancialTransaction],
        currencyService: CurrencyService
    ) -> [ChartsView.ChartData] {
        var tagDict: [String: Decimal] = [:]
        var tagTransactions: [String: [FinancialTransaction]] = [:]
        for tx in transactions {
            let amount = currencyService.convert(amount: abs(tx.amount), from: tx.currencyCode)
            if tx.tags.isEmpty {
                tagDict["無標籤", default: 0] += amount
                tagTransactions["無標籤", default: []].append(tx)
            } else {
                for tag in tx.tags {
                    tagDict[tag.name, default: 0] += amount
                    tagTransactions[tag.name, default: []].append(tx)
                }
            }
        }
        let sorted = tagDict.sorted { $0.value > $1.value }
        return sorted.enumerated().map { index, item in
            ChartsView.ChartData(
                key: item.key,
                name: item.key,
                amount: item.value,
                color: Color.generateDistinctColor(index: index, total: sorted.count),
                transactions: tagTransactions[item.key] ?? []
            )
        }
    }
}

private struct ReportTransactionListView: View {
    let title: String
    let transactions: [FinancialTransaction]

    var body: some View {
        let renderState = ReportTransactionListRenderState(transactions: transactions)

        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView("找不到交易", systemImage: "tray")
                } else {
                    List {
                        ForEach(renderState.groupedTransactions, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.items) { tx in
                                    TransactionRow(
                                        transaction: tx,
                                        transferCounterpart: renderState.transferCounterpartByID[tx.id]
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ReportTransactionListRenderState {
    let transferCounterpartByID: [UUID: TransferCounterpartInfo]
    let groupedTransactions: [(title: String, items: [FinancialTransaction])]

    init(transactions: [FinancialTransaction]) {
        self.transferCounterpartByID = TransferPresentationService.counterpartMap(transactions: transactions)
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
