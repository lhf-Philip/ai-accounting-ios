import SwiftUI
import SwiftData

struct EditCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var allCategories: [Category]
    
    // 傳入要編輯的物件
    @Bindable var category: Category
    
    // 暫存狀態 (避免直接修改原物件，直到按儲存)
    @State private var name: String = ""
    @State private var selectedIcon: String = ""
    @State private var selectedColorHex: String = ""
    @State private var selectedKind: CategoryKind = .both
    
    // 圖示列表 (與新增頁面保持一致)
    private let commonIcons: [String] = [
        "fork.knife", "cup.and.saucer.fill", "bus.fill", "car.fill",
        "cart.fill", "basket.fill", "house.fill", "bed.double.fill",
        "tshirt.fill", "cross.case.fill", "gamecontroller.fill", "tv.fill",
        "graduationcap.fill", "airplane", "gift.fill", "star.fill",
        "heart.fill", "pills.fill", "banknote.fill", "creditcard.fill"
    ]
    
    // 顏色列表
    private let commonColors: [String] = [
        "FF3B30", "007AFF", "34C759", "FF9500",
        "AF52DE", "8E8E93", "FF2D55", "5AC8FA",
        "FFCC00", "5856D6", "00C7BE", "A2845E"
    ]

    private var usedCategoryColorHexes: [String] {
        allCategories
            .filter { $0.id != category.id }
            .map { Color.normalizedRGBHex($0.colorHex) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. 名稱與預覽
                Section("分類名稱") {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color(hex: selectedColorHex))
                                .frame(width: 40, height: 40)
                            Image(systemName: selectedIcon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        TextField("分類名稱", text: $name)
                            .padding(.leading, 8)
                    }
                }
                
                Section("類型") {
                    Picker("類型", selection: $selectedKind) {
                        ForEach(CategoryKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // 2. 圖示選擇
                Section("選擇圖示") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(commonIcons, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                ZStack {
                                    if selectedIcon == icon {
                                        Circle()
                                            .fill(Color(hex: selectedColorHex).opacity(0.2))
                                    }
                                    Image(systemName: icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(selectedIcon == icon ? Color(hex: selectedColorHex) : .gray)
                                }
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 3. 顏色選擇
                Section("選擇顏色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(commonColors, id: \.self) { hex in
                                Button(action: {
                                    selectedColorHex = Color.normalizedRGBHex(hex)
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 40, height: 40)
                                        if selectedColorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.headline)
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }

                    Button {
                        selectedColorHex = Color.autoPickDistinctCategoryHex(
                            existingHexes: usedCategoryColorHexes,
                            preferredPalette: Color.defaultDistinctCategoryPalette
                        )
                    } label: {
                        Label("系統自動選色（避開已用顏色）", systemImage: "wand.and.stars")
                            .font(.subheadline)
                    }

                    if usedCategoryColorHexes.contains(Color.normalizedRGBHex(selectedColorHex)) {
                        Text("目前顏色已和其他分類重複，建議點擊系統自動選色。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("目前顏色未與現有分類衝突。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("編輯分類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        saveChanges()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // 初始化暫存數據
                name = category.name
                selectedIcon = category.icon
                selectedColorHex = Color.normalizedRGBHex(category.colorHex)
                selectedKind = category.kind
            }
        }
    }
    
    private func saveChanges() {
        category.name = name
        category.icon = selectedIcon
        category.colorHex = Color.normalizedRGBHex(selectedColorHex)
        category.kind = selectedKind
        dismiss()
    }
}
