import SwiftUI
import UniformTypeIdentifiers

struct BudgetAISuggestionView: View {
    @Environment(\.dismiss) private var dismiss

    let selectedMonthDate: Date
    let categories: [Category]
    let budgets: [CategoryMonthlyBudget]
    let transactions: [FinancialTransaction]
    let currencyService: CurrencyService
    let onApply: ([BudgetSuggestionItem]) -> Void

    private enum Phase {
        case configure
        case review
    }

    @State private var phase: Phase = .configure
    @State private var startDate: Date
    @State private var includeIncomeContext = false
    @State private var isImportingBackup = false
    @State private var uploadedBackup: FullBackupData?
    @State private var uploadedBackupFilename: String?
    @State private var isAnalyzing = false
    @State private var suggestions: [BudgetSuggestionItem] = []
    @State private var selectedSuggestionIDs: Set<UUID> = []
    @State private var errorMessage = ""
    @State private var showingError = false

    init(
        selectedMonthDate: Date,
        categories: [Category],
        budgets: [CategoryMonthlyBudget],
        transactions: [FinancialTransaction],
        currencyService: CurrencyService,
        onApply: @escaping ([BudgetSuggestionItem]) -> Void
    ) {
        self.selectedMonthDate = selectedMonthDate
        self.categories = categories
        self.budgets = budgets
        self.transactions = transactions
        self.currencyService = currencyService
        self.onApply = onApply

        let monthStart = BudgetService.monthStart(from: BudgetService.monthKey(from: selectedMonthDate)) ?? selectedMonthDate
        let defaultStartDate = Calendar.current.date(byAdding: .month, value: -3, to: monthStart) ?? monthStart
        _startDate = State(initialValue: defaultStartDate)
    }

    private var targetExpenseCategories: [Category] {
        categories.filter { $0.kind.supports(.expense) }
    }

    private var now: Date {
        Date()
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .configure:
                    configurationForm
                case .review:
                    reviewList
                }
            }
            .navigationTitle("AI 建議預算")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .configure ? "取消" : "返回") {
                        if phase == .review {
                            phase = .configure
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch phase {
                    case .configure:
                        Button(isAnalyzing ? "分析中..." : "開始分析") {
                            analyzeSuggestions()
                        }
                        .disabled(isAnalyzing || targetExpenseCategories.isEmpty)
                    case .review:
                        Button("套用") {
                            applySuggestions()
                        }
                        .disabled(selectedSuggestionIDs.isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
                handleBackupImport(result)
            }
            .alert("AI 預算建議失敗", isPresented: $showingError) {
                Button("了解", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var configurationForm: some View {
        Form {
            Section("分析範圍") {
                DatePicker("起始日", selection: $startDate, in: ...now, displayedComponents: [.date])
                HStack {
                    Text("結束日")
                    Spacer()
                    Text(now.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("目標月份")
                    Spacer()
                    Text(selectedMonthDate.formatted(.dateTime.year().month()))
                        .foregroundStyle(.secondary)
                }
            }

            Section("分析資料") {
                LabeledContent("支出資料") {
                    Text("一定包含")
                        .foregroundStyle(.secondary)
                }

                Toggle("加入收入資料作為上下文", isOn: $includeIncomeContext)

                Button {
                    isImportingBackup = true
                } label: {
                    Label(uploadedBackup == nil ? "上傳 JSON 備份（可選）" : "更換 JSON 備份", systemImage: "arrow.up.doc")
                }

                if let uploadedBackupFilename {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(uploadedBackupFilename)
                                .font(.subheadline)
                            Text("只會使用起始日至今的資料摘要")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("移除", role: .destructive) {
                            uploadedBackup = nil
                            self.uploadedBackupFilename = nil
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section("輸出方式") {
                Text("AI 只會建議支出分類的本月預算，收入資料只作參考。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("分析完成後會先讓你審核，再決定逐項或一次套用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if isAnalyzing {
                ProgressView("AI 分析中...")
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var reviewList: some View {
        List {
            Section("建議結果") {
                ForEach(suggestions) { suggestion in
                    Button {
                        toggleSelection(for: suggestion.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedSuggestionIDs.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedSuggestionIDs.contains(suggestion.id) ? .blue : .secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(categoryName(for: suggestion.categoryId))
                                    .font(.headline)
                                Text(suggestion.suggestedAmount.formatted(.currency(code: suggestion.currencyCode)))
                                    .font(.body.weight(.semibold))
                                Text(suggestion.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("全選") {
                    selectedSuggestionIDs = Set(suggestions.map(\.id))
                }
                Button("全部取消") {
                    selectedSuggestionIDs.removeAll()
                }
            }
        }
    }

    private func analyzeSuggestions() {
        isAnalyzing = true

        Task {
            do {
                let request = BudgetSuggestionRequest(
                    startDate: startDate,
                    endDate: now,
                    targetMonthDate: selectedMonthDate,
                    includeIncomeContext: includeIncomeContext,
                    mainCurrency: currencyService.mainCurrency,
                    appTransactions: transactions,
                    currentBudgets: budgets,
                    targetCategories: targetExpenseCategories,
                    currencyService: currencyService,
                    backupData: uploadedBackup
                )

                let result = try await BudgetSuggestionService.shared.suggestBudgets(for: request)
                await MainActor.run {
                    isAnalyzing = false
                    suggestions = result
                    selectedSuggestionIDs = Set(result.map(\.id))
                    if result.isEmpty {
                        errorMessage = "AI 沒有回傳可套用的預算建議。"
                        showingError = true
                    } else {
                        phase = .review
                    }
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func applySuggestions() {
        let selected = suggestions.filter { selectedSuggestionIDs.contains($0.id) }
        onApply(selected)
        dismiss()
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            uploadedBackup = try decoder.decode(FullBackupData.self, from: data)
            uploadedBackupFilename = url.lastPathComponent
        } catch {
            errorMessage = "讀取 JSON 備份失敗：\(error.localizedDescription)"
            showingError = true
        }
    }

    private func categoryName(for categoryID: UUID) -> String {
        targetExpenseCategories.first(where: { $0.id == categoryID })?.name ?? "未分類"
    }

    private func toggleSelection(for suggestionID: UUID) {
        if selectedSuggestionIDs.contains(suggestionID) {
            selectedSuggestionIDs.remove(suggestionID)
        } else {
            selectedSuggestionIDs.insert(suggestionID)
        }
    }
}
