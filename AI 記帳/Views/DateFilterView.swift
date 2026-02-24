import SwiftUI

enum FilterType: String, CaseIterable {
    case all = "全部"
    case year = "按年份"
    case month = "按月份"
    case day = "按日"
}

struct DateFilterView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var filterType: FilterType
    @Binding var selectedDate: Date
    
    var body: some View {
        NavigationStack {
            Form {
                Section("篩選模式") {
                    Picker("模式", selection: $filterType) {
                        ForEach(FilterType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if filterType == .year {
                    Section("選擇年份") {
                        Picker("年份", selection: yearBinding) {
                            ForEach(2020...2030, id: \.self) { year in
                                Text(String(format: "%d", year)).tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                } else if filterType == .month {
                    // 🔥 修正：使用並排 Wheel Picker
                    Section("選擇月份") {
                        HStack {
                            Picker("年份", selection: yearBinding) {
                                ForEach(2020...2030, id: \.self) { year in
                                    Text(String(format: "%d年", year)).tag(year)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            
                            Picker("月份", selection: monthBinding) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(String(format: "%d月", month)).tag(month)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        }
                    }
                } else if filterType == .day {
                    Section("選擇日期") {
                        DatePicker("選擇日期", selection: $selectedDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }
                }
            }
            .navigationTitle("篩選時間")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Logic Helpers
    
    private var yearBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.year, from: selectedDate) },
            set: { newYear in
                var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                components.year = newYear
                if let newDate = Calendar.current.date(from: components) {
                    selectedDate = newDate
                }
            }
        )
    }
    
    private var monthBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.month, from: selectedDate) },
            set: { newMonth in
                var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                components.month = newMonth
                if let newDate = Calendar.current.date(from: components) {
                    selectedDate = newDate
                }
            }
        )
    }
}
