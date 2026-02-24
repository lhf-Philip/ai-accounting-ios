import SwiftUI
import SwiftData
import Charts

struct TagReportView: View {
    @Query private var transactions: [FinancialTransaction]
    @Query private var tags: [Tag]
    
    @State private var selectedTag: Tag?
    
    var body: some View {
        VStack {
            // 標籤選擇器
            if tags.isEmpty {
                Text("尚無標籤資料")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags) { tag in
                            Button(action: { selectedTag = tag }) {
                                Text(tag.name)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedTag == tag ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(selectedTag == tag ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding()
                }
            }
            
            // 圖表內容
            if let tag = selectedTag {
                let tagTransactions = transactions.filter { $0.tags.contains(tag) }
                
                if tagTransactions.isEmpty {
                    ContentUnavailableView("此標籤無交易", systemImage: "tag.slash")
                } else {
                    List {
                        Section("分類佔比 (\(tag.name))") {
                            Chart(groupByCategory(transactions: tagTransactions), id: \.category.name) { item in
                                SectorMark(
                                    angle: .value("金額", item.amount),
                                    innerRadius: .ratio(0.6)
                                )
                                .foregroundStyle(by: .value("分類", item.category.name))
                            }
                            .frame(height: 250)
                        }
                        
                        Section("交易列表") {
                            ForEach(tagTransactions) { tx in
                                HStack {
                                    Text(tx.category?.name ?? "未分類")
                                    Spacer()
                                    Text(tx.amount, format: .currency(code: "HKD"))
                                        .foregroundStyle(tx.amount < 0 ? .red : .green)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("請選擇一個標籤查看分析").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle("標籤報表")
        .onAppear {
            if selectedTag == nil { selectedTag = tags.first }
        }
    }
    
    // 簡單的分類加總邏輯
    struct CategorySum { let category: Category; let amount: Decimal }
    
    func groupByCategory(transactions: [FinancialTransaction]) -> [CategorySum] {
        let grouped = Dictionary(grouping: transactions) { $0.category }
        return grouped.compactMap { (cat, txs) in
            guard let cat = cat else { return nil }
            let sum = abs(txs.reduce(0) { $0 + $1.amount })
            return CategorySum(category: cat, amount: sum)
        }.sorted { $0.amount > $1.amount }
    }
}
