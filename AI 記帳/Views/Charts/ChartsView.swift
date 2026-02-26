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
    
    // 互動狀態
    @State private var selectedSegmentName: String?
    @State private var selectedTagForDetail: String?
    
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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 頂部控制列
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
                        .onChange(of: flowMode) { selectedTagForDetail = nil; selectedSegmentName = nil }
                        
                        Picker("模式", selection: $chartMode) {
                            ForEach(ChartMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: chartMode) { selectedTagForDetail = nil; selectedSegmentName = nil }
                    }
                }
                .padding()
                
                // 內容區
                ScrollView {
                    if currentData.isEmpty {
                        ContentUnavailableView(flowMode.emptyTitle, systemImage: "chart.pie", description: Text("試試切換日期或記一筆帳"))
                            .padding(.top, 40)
                    } else if chartMode == .tag && selectedTagForDetail != nil {
                        tagDetailView
                    } else {
                        mainChartView
                    }
                }
                
                if !budgetAlerts.isEmpty && flowMode == .expense {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本月超支提醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(budgetAlerts.prefix(3)) { status in
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
            .navigationTitle("報表")
            .sheet(isPresented: $showingFilterSheet) {
                DateFilterView(filterType: $filterType, selectedDate: $selectedDate)
            }
        }
    }
    
    // MARK: - 主圖表視圖
    var mainChartView: some View {
        VStack(spacing: 24) {
            chartView(data: currentData)
                .frame(height: 300)
                .padding(.horizontal)
            
            LazyVStack(spacing: 16) {
                ForEach(currentData, id: \.name) { item in
                    Button(action: {
                        if chartMode == .tag {
                            withAnimation { selectedTagForDetail = item.name; selectedSegmentName = nil }
                        } else {
                            withAnimation { selectedSegmentName = (selectedSegmentName == item.name) ? nil : item.name }
                        }
                    }) {
                        rowView(item: item, total: totalAmount(data: currentData), isDrillDown: chartMode == .tag)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal).padding(.bottom, 20)
        }
    }
    
    // MARK: - 標籤詳情視圖
    var tagDetailView: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: { withAnimation { selectedTagForDetail = nil; selectedSegmentName = nil } }) {
                    HStack {
                        Image(systemName: "arrow.left.circle.fill").font(.title2)
                        Text(selectedTagForDetail ?? "").font(.title3).bold()
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            
            let detailData = getCategoryBreakdown(for: selectedTagForDetail!)
            
            if detailData.isEmpty {
                ContentUnavailableView("此標籤無分類數據", systemImage: "tag.slash")
            } else {
                chartView(data: detailData)
                    .frame(height: 250)
                    .padding(.horizontal)
                
                LazyVStack(spacing: 16) {
                    ForEach(detailData, id: \.name) { item in
                        Button(action: {
                            withAnimation { selectedSegmentName = (selectedSegmentName == item.name) ? nil : item.name }
                        }) {
                            rowView(item: item, total: totalAmount(data: detailData), isDrillDown: false)
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
        let displayTotal = selectedSegmentName != nil ? (data.first(where: { $0.name == selectedSegmentName })?.amount ?? 0) : total
        return ZStack {
            Chart(data, id: \.name) { item in
                SectorMark(
                    angle: .value("金額", item.amount),
                    innerRadius: .ratio(0.65),
                    outerRadius: selectedSegmentName == item.name ? .ratio(1.0) : .ratio(0.9),
                    angularInset: 2.0
                )
                .cornerRadius(6)
                .foregroundStyle(item.color)
                .opacity(selectedSegmentName == nil ? 1.0 : (selectedSegmentName == item.name ? 1.0 : 0.3))
            }
            .chartAngleSelection(value: $selectedSegmentName)
            VStack {
                Text(selectedSegmentName ?? flowMode.totalTitle).font(.callout).foregroundStyle(.secondary)
                Text(displayTotal.formatted(.currency(code: currencyService.mainCurrency)))
                    .font(.title2).bold().foregroundStyle(.primary)
            }
        }
    }
    
    func rowView(item: ChartData, total: Decimal, isDrillDown: Bool) -> some View {
        let percent = total > 0 ? (item.amount / total * 100) : 0
        let isSelected = (selectedSegmentName == item.name)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(item.color).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body).fontWeight(.medium)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.1))
                        Capsule().fill(item.color).frame(width: geo.size.width * CGFloat(NSDecimalNumber(decimal: percent).doubleValue / 100))
                    }
                }.frame(height: 6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.amount.formatted(.currency(code: currencyService.mainCurrency))).font(.body).bold()
                HStack(spacing: 4) {
                    Text("\(percent.formatted(.number.precision(.fractionLength(1))))%")
                    if isDrillDown { Image(systemName: "chevron.right") }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1))
    }
    
    // MARK: - Data Logic
    struct ChartData {
        let name: String
        let amount: Decimal
        let color: Color
    }
    
    var currentData: [ChartData] {
        if chartMode == .category {
            let grouped = Dictionary(grouping: filteredTransactions) { $0.category }
            let sorted = grouped.sorted {
                let sum0 = $0.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
                let sum1 = $1.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
                return sum0 > sum1
            }
            // 🔥 修復：優先使用分類的 colorHex，如果沒有則使用灰色
            return sorted.enumerated().map { (index, item) in
                let total = item.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
                let displayColor: Color
                if let category = item.key {
                    displayColor = Color(hex: category.colorHex)
                } else {
                    displayColor = .gray
                }
                return ChartData(name: item.key?.name ?? "未分類", amount: total, color: displayColor)
            }
        } else {
            var tagDict: [String: Decimal] = [:]
            for tx in filteredTransactions {
                let amount = currencyService.convert(amount: abs(tx.amount), from: tx.currencyCode)
                if tx.tags.isEmpty { tagDict["無標籤", default: 0] += amount }
                else { for tag in tx.tags { tagDict[tag.name, default: 0] += amount } }
            }
            let sorted = tagDict.sorted { $0.value > $1.value }
            return sorted.enumerated().map { (index, item) in
                ChartData(name: item.key, amount: item.value, color: Color.generateDistinctColor(index: index, total: sorted.count))
            }
        }
    }
    
    func getCategoryBreakdown(for tagName: String) -> [ChartData] {
        let tagTransactions = filteredTransactions.filter { tx in
            if tagName == "無標籤" { return tx.tags.isEmpty }
            return tx.tags.contains { $0.name == tagName }
        }
        let grouped = Dictionary(grouping: tagTransactions) { $0.category }
        let sorted = grouped.sorted {
            let sum0 = $0.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
            let sum1 = $1.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
            return sum0 > sum1
        }
        // 🔥 修復：鑽取詳情時也使用分類顏色
        return sorted.enumerated().map { (index, item) in
            let total = item.value.reduce(0) { $0 + currencyService.convert(amount: abs($1.amount), from: $1.currencyCode) }
            let displayColor: Color
            if let category = item.key {
                displayColor = Color(hex: category.colorHex)
            } else {
                displayColor = .gray
            }
            return ChartData(name: item.key?.name ?? "未分類", amount: total, color: displayColor)
        }
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
    
    var filteredExpenses: [FinancialTransaction] {
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
    
    var filteredTransactions: [FinancialTransaction] { filteredExpenses }
    
    var budgetAlerts: [BudgetStatus] {
        let key = BudgetService.monthKey(from: Date())
        return BudgetService.statuses(for: key, budgets: budgets, transactions: transactions, currencyService: currencyService)
            .filter { $0.ratio >= 1 }
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
