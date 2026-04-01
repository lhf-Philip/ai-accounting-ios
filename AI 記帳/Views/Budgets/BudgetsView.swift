import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \CategoryMonthlyBudget.monthKey, order: .reverse) private var budgets: [CategoryMonthlyBudget]
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
        let color: Color = status.isOverBudget ? .red : (status.ratio >= 0.85 ? .orange : .green)
        
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
        }
        .padding(.vertical, 4)
    }
    
    private func deleteBudget(_ budget: CategoryMonthlyBudget) {
        modelContext.delete(budget)
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

        try? modelContext.save()
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
                            ForEach(currencies, id: \.self) { code in
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
            dismiss()
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
        
        dismiss()
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
