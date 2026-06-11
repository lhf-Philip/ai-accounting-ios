import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \CategoryMonthlyBudget.monthKey, order: .reverse) private var budgets: [CategoryMonthlyBudget]
    @Query(sort: \BudgetSettings.updatedAt, order: .reverse) private var budgetSettingsRecords: [BudgetSettings]
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @StateObject private var currencyService = CurrencyService.shared
    
    @State private var selectedMonthDate = Date()
    @State private var budgetToEdit: CategoryMonthlyBudget?
    @State private var showingAddBudget = false
    @State private var showingOnlyAlerts = false
    @State private var showingAISuggestions = false
    
    private var monthKey: String {
        BudgetService.monthKey(from: selectedMonthDate)
    }

    private var budgetSettings: BudgetSettings? {
        budgetSettingsRecords.first
    }
    
    private var monthStatuses: [BudgetStatus] {
        BudgetService.statuses(
            for: monthKey,
            budgets: budgets,
            transactions: transactions,
            currencyService: currencyService
        )
    }
    
    private var visibleStatuses: [BudgetStatus] {
        if showingOnlyAlerts {
            return monthStatuses.filter { $0.ratio >= 1 }
        }
        return monthStatuses
    }
    
    private var availableExpenseCategories: [Category] {
        categories.filter { $0.kind.supports(.expense) }
    }
    
    var body: some View {
        List {
            Section("月份") {
                DatePicker("預算月份", selection: $selectedMonthDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                Toggle("只顯示提醒", isOn: $showingOnlyAlerts)
            }

            if let budgetSettings {
                Section("預算規則") {
                    Picker("結轉方式", selection: Binding(
                        get: { budgetSettings.carryOverMode },
                        set: { mode in
                            budgetSettings.carryOverMode = mode
                            persistBudgetSettings()
                            applyCarryOverIfNeeded()
                        }
                    )) {
                        ForEach(BudgetCarryOverMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Stepper(
                        value: Binding(
                            get: { Int(truncating: NSDecimalNumber(decimal: budgetSettings.alertThresholdPercent)) },
                            set: { value in
                                budgetSettings.alertThresholdPercent = Decimal(value)
                                budgetSettings.updatedAt = Date()
                                persistBudgetSettings()
                            }
                        ),
                        in: 50...100,
                        step: 5
                    ) {
                        Text("提醒門檻：\(Int(truncating: NSDecimalNumber(decimal: budgetSettings.alertThresholdPercent)))%")
                    }

                    LabeledContent("預測方式", value: budgetSettings.forecastMode.displayName)
                    Text(carryOverDescription(for: budgetSettings.carryOverMode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if visibleStatuses.isEmpty {
                Section {
                    ContentUnavailableView(
                        "本月無預算",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("請先新增分類月預算")
                    )
                }
            } else {
                Section("分類預算") {
                    ForEach(visibleStatuses) { status in
                        Button {
                            budgetToEdit = status.budget
                        } label: {
                            budgetRow(status)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteBudget(status.budget)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("預算與超支提醒")
        .task {
            ensureBudgetSettings()
            applyCarryOverIfNeeded()
        }
        .onChange(of: selectedMonthDate) { _, _ in
            applyCarryOverIfNeeded()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingAISuggestions = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .disabled(availableExpenseCategories.isEmpty)

                Button {
                    showingAddBudget = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(availableExpenseCategories.isEmpty)
            }
        }
        .sheet(isPresented: $showingAddBudget) {
            BudgetEditorView(
                existingBudget: nil,
                monthDate: selectedMonthDate,
                allBudgets: budgets,
                categories: availableExpenseCategories
            )
        }
        .sheet(item: $budgetToEdit) { budget in
            BudgetEditorView(
                existingBudget: budget,
                monthDate: selectedMonthDate,
                allBudgets: budgets,
                categories: availableExpenseCategories
            )
        }
        .sheet(isPresented: $showingAISuggestions) {
            BudgetAISuggestionView(
                selectedMonthDate: selectedMonthDate,
                categories: categories,
                budgets: budgets,
                transactions: transactions,
                currencyService: currencyService
            ) { suggestions in
                applyAISuggestions(suggestions)
            }
        }
    }
    
    @ViewBuilder
    private func budgetRow(_ status: BudgetStatus) -> some View {
        let budget = status.budget
        let categoryName = budget.category?.name ?? "未分類"
        let progress = min(max(Double(NSDecimalNumber(decimal: status.ratio).doubleValue), 0), 1.5)
        let overBy = abs(status.remaining)
        let threshold = (budgetSettings?.alertThresholdPercent ?? 85) / 100
        let forecast = BudgetService.forecast(for: status)
        let color: Color = status.isOverBudget ? .red : (status.ratio >= threshold ? .orange : .green)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(categoryName)
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Text(status.spent.formatted(.currency(code: budget.currencyCode)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(status.isOverBudget ? .red : .primary)
            }
            
            ProgressView(value: progress, total: 1.0)
                .tint(color)
            
            HStack {
                Text("預算：\(budget.amount.formatted(.currency(code: budget.currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if status.isOverBudget {
                    Text("超支：\(overBy.formatted(.currency(code: budget.currencyCode)))")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("剩餘：\(status.remaining.formatted(.currency(code: budget.currencyCode)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("月底預測：\(forecast.projectedSpent.formatted(.currency(code: budget.currencyCode)))")
                    .font(.caption2)
                    .foregroundStyle(forecast.isProjectedOverBudget ? .red : .secondary)
                Spacer()
                if forecast.isProjectedOverBudget {
                    Text("預計超支 \(abs(forecast.projectedRemaining).formatted(.currency(code: budget.currencyCode)))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("預計剩餘 \(forecast.projectedRemaining.formatted(.currency(code: budget.currencyCode)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func ensureBudgetSettings() {
        guard budgetSettingsRecords.isEmpty else { return }
        modelContext.insert(BudgetSettings())
        persistBudgetSettings()
    }

    private func persistBudgetSettings() {
        do {
            try modelContext.save()
        } catch {
            print("儲存預算設定失敗: \(error)")
        }
    }

    private func carryOverDescription(for mode: BudgetCarryOverMode) -> String {
        switch mode {
        case .none:
            return "新月份不會自動建立預算。"
        case .unusedOnly:
            return "新月份會把上月剩餘金額加到同分類預算。"
        case .overspendOnly:
            return "新月份會扣減上月超支金額。"
        case .netBalance:
            return "新月份會把上月剩餘或超支都結轉。"
        }
    }

    private func applyCarryOverIfNeeded() {
        guard let settings = budgetSettings,
              settings.carryOverMode != .none,
              let previousMonthKey = BudgetService.previousMonthKey(from: monthKey)
        else { return }

        let currentCategoryIDs = Set(budgets.compactMap { budget -> UUID? in
            guard budget.monthKey == monthKey else { return nil }
            return budget.category?.id
        })

        let previousStatuses = BudgetService.statuses(
            for: previousMonthKey,
            budgets: budgets,
            transactions: transactions,
            currencyService: currencyService
        )

        var inserted = false
        for status in previousStatuses {
            guard let category = status.budget.category,
                  !currentCategoryIDs.contains(category.id)
            else { continue }

            let amount = BudgetService.carryOverAmount(
                previousBudgetAmount: status.budget.amount,
                previousRemaining: status.remaining,
                mode: settings.carryOverMode
            )
            guard amount > 0 else { continue }

            modelContext.insert(CategoryMonthlyBudget(
                monthKey: monthKey,
                amount: amount,
                currencyCode: status.budget.currencyCode,
                isEnabled: status.budget.isEnabled,
                category: category
            ))
            inserted = true
        }

        guard inserted else { return }
        do {
            try modelContext.save()
            try BudgetHistoryService.shared.syncAll(modelContext: modelContext, currencyService: currencyService)
        } catch {
            print("套用預算結轉失敗: \(error)")
        }
    }
    
    private func deleteBudget(_ budget: CategoryMonthlyBudget) {
        modelContext.delete(budget)
        do {
            try modelContext.save()
            try BudgetHistoryService.shared.syncAll(modelContext: modelContext, currencyService: currencyService)
        } catch {
            print("刪除預算後同步歷史失敗: \(error)")
        }
    }

    private func applyAISuggestions(_ suggestions: [BudgetSuggestionItem]) {
        let targetMonthKey = BudgetService.monthKey(from: selectedMonthDate)

        for suggestion in suggestions {
            guard let category = availableExpenseCategories.first(where: { $0.id == suggestion.categoryId }) else {
                continue
            }

            if let existing = budgets.first(where: {
                $0.monthKey == targetMonthKey && $0.category?.id == category.id
            }) {
                existing.amount = currencyService.convert(
                    amount: suggestion.suggestedAmount,
                    from: suggestion.currencyCode,
                    to: existing.currencyCode
                )
                existing.updatedAt = Date()
                existing.isEnabled = true
            } else {
                let budget = CategoryMonthlyBudget(
                    monthKey: targetMonthKey,
                    amount: suggestion.suggestedAmount,
                    currencyCode: suggestion.currencyCode,
                    isEnabled: true,
                    category: category
                )
                modelContext.insert(budget)
            }
        }

        do {
            try modelContext.save()
            try BudgetHistoryService.shared.syncAll(modelContext: modelContext, currencyService: currencyService)
        } catch {
            print("套用 AI 預算建議後同步歷史失敗: \(error)")
        }
    }

}

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("mainCurrency") private var mainCurrency: String = "HKD"
    
    let existingBudget: CategoryMonthlyBudget?
    let monthDate: Date
    let allBudgets: [CategoryMonthlyBudget]
    let categories: [Category]
    
    @State private var selectedCategory: Category?
    @State private var selectedMonthDate = Date()
    @State private var amountString = ""
    @State private var currencyCode = "HKD"
    @State private var isEnabled = true
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var availableCurrencies: [String] {
        currencies.contains(currencyCode) ? currencies : [currencyCode] + currencies
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("分類與月份") {
                    Picker("分類", selection: $selectedCategory) {
                        Text("選擇分類").tag(nil as Category?)
                        ForEach(categories) { category in
                            Text(category.name).tag(category as Category?)
                        }
                    }
                    
                    DatePicker("月份", selection: $selectedMonthDate, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                }
                
                Section("預算") {
                    HStack {
                        Picker("幣種", selection: $currencyCode) {
                            ForEach(availableCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .frame(width: 90)
                        
                        TextField("金額", text: $amountString)
                            .keyboardType(.decimalPad)
                    }
                    Toggle("啟用", isOn: $isEnabled)
                }
            }
            .standardKeyboardBehavior()
            .navigationTitle(existingBudget == nil ? "新增預算" : "編輯預算")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                }
            }
            .alert("無法儲存", isPresented: $showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear(perform: setup)
        }
    }
    
    private func setup() {
        if let existingBudget {
            selectedCategory = existingBudget.category
            selectedMonthDate = BudgetService.monthStart(from: existingBudget.monthKey) ?? monthDate
            amountString = NSDecimalNumber(decimal: existingBudget.amount).stringValue
            currencyCode = existingBudget.currencyCode
            isEnabled = existingBudget.isEnabled
        } else {
            selectedMonthDate = monthDate
            currencyCode = mainCurrency
            isEnabled = true
        }
    }
    
    private func save() {
        guard let selectedCategory else {
            showError("請選擇分類")
            return
        }
        
        guard let amount = Decimal(string: amountString), amount > 0 else {
            showError("請輸入大於 0 的預算金額")
            return
        }
        
        let key = BudgetService.monthKey(from: selectedMonthDate)
        
        // 避免同一分類同月份重複，找到既有資料就覆寫
        let duplicate = allBudgets.first { budget in
            budget.id != existingBudget?.id &&
            budget.monthKey == key &&
            budget.category?.id == selectedCategory.id
        }
        
        if let duplicate {
            duplicate.amount = amount
            duplicate.currencyCode = currencyCode
            duplicate.isEnabled = isEnabled
            duplicate.updatedAt = Date()
            if let existingBudget, existingBudget.id != duplicate.id {
                modelContext.delete(existingBudget)
            }
            if persistBudgetChanges() {
                dismiss()
            }
            return
        }
        
        if let existingBudget {
            existingBudget.category = selectedCategory
            existingBudget.monthKey = key
            existingBudget.amount = amount
            existingBudget.currencyCode = currencyCode
            existingBudget.isEnabled = isEnabled
            existingBudget.updatedAt = Date()
        } else {
            let budget = CategoryMonthlyBudget(
                monthKey: key,
                amount: amount,
                currencyCode: currencyCode,
                isEnabled: isEnabled,
                category: selectedCategory
            )
            modelContext.insert(budget)
        }

        if persistBudgetChanges() {
            dismiss()
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func persistBudgetChanges() -> Bool {
        do {
            try modelContext.save()
            try BudgetHistoryService.shared.syncAll(modelContext: modelContext, currencyService: CurrencyService.shared)
            return true
        } catch {
            showError("儲存預算後同步歷史失敗：\(error.localizedDescription)")
            return false
        }
    }
}
