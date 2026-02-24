import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    
    @State private var showingAddCategory = false
    @State private var categoryToEdit: Category? // 用於控制編輯彈窗
    
    var body: some View {
        List {
            ForEach(categories) { category in
                HStack(spacing: 16) {
                    // Icon Circle
                    ZStack {
                        Circle()
                            .fill(Color(hex: category.colorHex))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: category.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text(category.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle()) // 讓整個區域可點擊
                .onTapGesture {
                    categoryToEdit = category
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteCategory(category)
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                    
                    Button {
                        categoryToEdit = category
                    } label: {
                        Label("編輯", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("分類管理")
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView(
                    "尚無分類",
                    systemImage: "tray",
                    description: Text("點擊右上角的 + 新增您的第一個分類")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddCategory = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView()
                .presentationDetents([.large])
        }
        .sheet(item: $categoryToEdit) { category in
            EditCategoryView(category: category)
                .presentationDetents([.large])
        }
    }
    
    private func deleteCategory(_ category: Category) {
        modelContext.delete(category)
    }
}
