import SwiftUI
import SwiftData

struct HomeDashboardView: View {
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @Query(sort: \AdvanceCase.date, order: .reverse) private var advanceCases: [AdvanceCase]
    @StateObject private var currencyService = CurrencyService.shared
    @State private var filterType: FilterType = .month
    @State private var selectedDate: Date = Date()
    @State private var showingFilterSheet = false

    let onQuickAdd: () -> Void
    let onOpenGuide: () -> Void
    let onOpenLedger: () -> Void
    let onOpenReports: () -> Void
    let onOpenAccounts: () -> Void

    private var filteredTransactions: [FinancialTransaction] {
        transactions.filter { matchesFilter(date: $0.date) }
    }

    private var periodExpenseMain: Decimal {
        filteredTransactions
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { partial, tx in
                partial + currencyService.convert(amount: abs(tx.amount), from: tx.currencyCode)
            }
    }

    private var periodIncomeMain: Decimal {
        filteredTransactions
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { partial, tx in
                partial + currencyService.convert(amount: abs(tx.amount), from: tx.currencyCode)
            }
    }

    private var periodNetMain: Decimal {
        periodIncomeMain - periodExpenseMain
    }

    private var filteredAdvanceCases: [AdvanceCase] {
        advanceCases.filter { matchesFilter(date: $0.date) }
    }

    private var periodOutstandingAdvance: Decimal {
        filteredAdvanceCases
            .reduce(Decimal.zero) { partial, advanceCase in
                let outstanding = AdvanceService.outstandingAmount(for: advanceCase)
                return partial + currencyService.convert(amount: outstanding, from: advanceCase.currencyCode)
            }
    }

    private var periodRecordCount: Int {
        filteredTransactions.filter { $0.type != .transfer }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryHeader
                    filterControlRow
                    quickActionPanel
                    overviewCards
                    shortcutsPanel
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .prominentInlineTitle("總覽")
            .task {
                await currencyService.fetchRates()
            }
            .sheet(isPresented: $showingFilterSheet) {
                DateFilterView(filterType: $filterType, selectedDate: $selectedDate)
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("歡迎使用 AI 記帳")
                .font(.title2)
                .fontWeight(.bold)
            Text("今天是 \(Date.now.formatted(date: .complete, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(filterDisplayString)已記錄 \(periodRecordCount) 筆收入/支出")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterControlRow: some View {
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
    }

    private var quickActionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快速開始")
                .font(.headline)
            HStack(spacing: 10) {
                Button {
                    onQuickAdd()
                } label: {
                    Label("新增記錄", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onOpenGuide()
                } label: {
                    Label("使用教學", systemImage: "book.pages")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var overviewCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(filterDisplayString)重點（\(currencyService.mainCurrency)）")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryCard(
                    title: "收入",
                    value: periodIncomeMain.formatted(.currency(code: currencyService.mainCurrency)),
                    tint: .green,
                    icon: "arrow.down.circle"
                )

                summaryCard(
                    title: "支出",
                    value: periodExpenseMain.formatted(.currency(code: currencyService.mainCurrency)),
                    tint: .red,
                    icon: "arrow.up.circle"
                )

                summaryCard(
                    title: "淨收支",
                    value: periodNetMain.formatted(.currency(code: currencyService.mainCurrency)),
                    tint: periodNetMain >= 0 ? .blue : .orange,
                    icon: "equal.circle"
                )

                summaryCard(
                    title: "代墊待收",
                    value: periodOutstandingAdvance.formatted(.currency(code: currencyService.mainCurrency)),
                    tint: .purple,
                    icon: "person.2"
                )
            }
        }
    }

    private var shortcutsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("功能入口")
                .font(.headline)

            VStack(spacing: 8) {
                panelButton(title: "查看帳目明細", subtitle: "搜尋、篩選、編輯所有交易", icon: "list.bullet") {
                    onOpenLedger()
                }
                panelButton(title: "查看收支報表", subtitle: "依分類與標籤分析收入/支出", icon: "chart.pie") {
                    onOpenReports()
                }
                panelButton(title: "管理帳戶", subtitle: "查看資產估算與各幣別餘額", icon: "creditcard") {
                    onOpenAccounts()
                }
            }
        }
    }

    private func summaryCard(title: String, value: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func panelButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.blue)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var filterDisplayString: String {
        let formatter = DateFormatter()
        switch filterType {
        case .all:
            return "全部紀錄"
        case .year:
            return "\(Calendar.current.component(.year, from: selectedDate))年"
        case .month:
            formatter.dateFormat = "yyyy年 M月"
            return formatter.string(from: selectedDate)
        case .day:
            formatter.dateFormat = "M月d日"
            return formatter.string(from: selectedDate)
        }
    }

    private func matchesFilter(date: Date) -> Bool {
        let calendar = Calendar.current
        switch filterType {
        case .all:
            return true
        case .year:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .year)
        case .month:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
        case .day:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .day)
        }
    }
}
