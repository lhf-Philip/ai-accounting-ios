import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Form States
    @State private var name: String = ""
    @State private var selectedIcon: String = "fork.knife"
    @State private var selectedColorHex: String = "007AFF" // 預設藍色
    @State private var systemColor: Color = Color(hex: "007AFF")
    @State private var selectedKind: CategoryKind = .expense
    
    // 預定義的圖示列表
    private let commonIcons: [String] = [
        "fork.knife", "cup.and.saucer.fill", "bus.fill", "car.fill",
        "cart.fill", "basket.fill", "house.fill", "bed.double.fill",
        "tshirt.fill", "cross.case.fill", "gamecontroller.fill", "tv.fill",
        "graduationcap.fill", "airplane", "gift.fill", "star.fill"
    ]
    
    // 預定義的顏色列表 (Hex Strings)
    // 對應: 紅, 藍, 綠, 橘, 紫, 灰, 粉, 青
    private let commonColors: [String] = [
        "FF3B30", "007AFF", "34C759", "FF9500",
        "AF52DE", "8E8E93", "FF2D55", "5AC8FA"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 1. 名稱與預覽
                Section("分類名稱") {
                    HStack {
                        // 即時預覽圖示
                        ZStack {
                            Circle()
                                .fill(Color(hex: selectedColorHex))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: selectedIcon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        TextField("例如: 早餐、交通", text: $name)
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
                
                // MARK: - 2. 圖示選擇
                Section("選擇圖示") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(commonIcons, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                            }) {
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
                            .buttonStyle(.plain) // 移除 List row 的點擊效果
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // MARK: - 3. 顏色選擇
                Section("選擇顏色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(commonColors, id: \.self) { hex in
                                Button(action: {
                                    selectedColorHex = hex
                                    systemColor = Color(hex: hex)
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 40, height: 40)
                                        
                                        // 選中時顯示打勾
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

                    ColorPicker("系統選色", selection: $systemColor, supportsOpacity: false)
                        .onChange(of: systemColor) { _, newValue in
                            guard let uniqueHex = Color.uniqueSystemColorHex(
                                from: newValue,
                                avoiding: Set(commonColors)
                            ) else { return }
                            selectedColorHex = uniqueHex
                        }

                    if !commonColors.contains(Color.normalizedRGBHex(selectedColorHex)) {
                        Text("目前為系統自訂色（已避開手動色盤）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("新增分類")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                systemColor = Color(hex: selectedColorHex)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        saveCategory()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveCategory() {
        let newCategory = Category(
            name: name,
            icon: selectedIcon,
            colorHex: Color.normalizedRGBHex(selectedColorHex),
            kind: selectedKind
        )
        
        modelContext.insert(newCategory)
        dismiss()
    }
}

#Preview {
    AddCategoryView()
}
