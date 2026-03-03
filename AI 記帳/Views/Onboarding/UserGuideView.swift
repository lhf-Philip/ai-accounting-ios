import SwiftUI

struct UserGuideView: View {
    @Environment(\.dismiss) private var dismiss

    let isFirstLaunch: Bool
    var onCompleted: (() -> Void)?

    init(isFirstLaunch: Bool = false, onCompleted: (() -> Void)? = nil) {
        self.isFirstLaunch = isFirstLaunch
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroSection
                    sectionCard(
                        title: "1. 先建立帳戶",
                        icon: "creditcard",
                        points: [
                            "在「帳戶」頁新增現金、銀行、信用卡或借貸帳戶。",
                            "每個帳戶可設定基礎餘額與幣別，資產估算會自動換算。"
                        ]
                    )

                    sectionCard(
                        title: "2. 記錄日常收支",
                        icon: "plus.circle",
                        points: [
                            "使用右下角「新增」按鈕建立收入、支出、轉帳、借貸或代墊。",
                            "每筆交易可帶分類、標籤、備註與交易幣別。",
                            "轉帳與代墊支援完整編輯，不需刪除重建。"
                        ]
                    )

                    sectionCard(
                        title: "3. 看懂報表",
                        icon: "chart.pie",
                        points: [
                            "在「報表」切換收入/支出、分類/標籤檢視。",
                            "點擊分類或標籤可查看對應交易明細。"
                        ]
                    )

                    sectionCard(
                        title: "4. 備份與資料安全",
                        icon: "externaldrive",
                        points: [
                            "在「設定 > 資料安全」設定自動備份資料夾。",
                            "建議定期匯出 JSON 全機備份；換機時可直接還原。",
                            "API 金鑰儲存在 iOS Keychain，不會寫進專案。"
                        ]
                    )

                    sectionCard(
                        title: "5. 進階功能",
                        icon: "wrench.and.screwdriver",
                        points: [
                            "代墊追蹤：管理多人分帳、還款進度與入帳帳戶。",
                            "預算與超支提醒：按分類管理每月上限。",
                            "資料健康檢查：快速找出連結或資料異常。"
                        ]
                    )
                }
                .padding()
            }
            .navigationTitle("使用教學")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isFirstLaunch {
                        Button("關閉") {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isFirstLaunch ? "開始使用" : "完成") {
                        onCompleted?()
                        dismiss()
                    }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("一個畫面掌握收支、轉帳、借貸與代墊。")
                .font(.title3)
                .fontWeight(.bold)
            Text("建議流程：先建立帳戶，再開始記帳，最後到報表與設定確認資料。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionCard(title: String, icon: String, points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            ForEach(points, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .padding(.top, 3)
                    Text(point)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
