import SwiftUI
import PhotosUI
import SwiftData

struct ScanReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    
    // 狀態
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var userNote: String = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // 如果分析成功，跳轉到確認頁面
    @State private var scannedInfo: ReceiptInfo?
    @State private var navigateToConfirm = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 1. 圖片顯示區
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 300)
                        .cornerRadius(12)
                        .onTapGesture {
                            // 點擊更換
                            selectedItem = nil
                        }
                } else {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 300)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                        .foregroundStyle(.gray)
                                )
                            
                            VStack {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.blue)
                                Text("上傳或拍攝單據")
                                    .font(.headline)
                            }
                        }
                    }
                }
                
                // 2. 備註輸入區
                VStack(alignment: .leading) {
                    Text("備註 (可選)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("例如：我和 John AA制，我付漢堡錢", text: $userNote)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // 3. 分析按鈕
                Button(action: analyzeImage) {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .tint(.white)
                            Text("AI 分析中...")
                        } else {
                            Image(systemName: "sparkles")
                            Text("開始智能識別")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedImage == nil || isAnalyzing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(selectedImage == nil || isAnalyzing)
                .padding()
                
                Text("使用 Gemini AI 免費版技術，圖片將上傳至 Google 處理")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("掃描單據")
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                    }
                }
            }
            .alert("分析失敗", isPresented: $showingError) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知錯誤")
            }
            // 導航到新增頁面 (帶入資料)
            .navigationDestination(isPresented: $navigateToConfirm) {
                if let info = scannedInfo, let img = selectedImage {
                    // 這裡我們重用 AddTransactionView，但需要給它加一個 init
                    // 為了簡單，我這裡創建一個專門的 ConfirmView，或者你需要修改 AddTransactionView 讓它接受預設值
                    ScannedResultView(info: info, receiptImage: img)
                }
            }
        }
    }
    
    private func analyzeImage() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        errorMessage = nil
        
        Task {
            do {
                let categoryNames = categories.map(\.name)
                let result = try await GeminiService.shared.analyzeReceipt(
                    image: image,
                    userNote: userNote,
                    categoryCandidates: categoryNames
                )
                DispatchQueue.main.async {
                    self.scannedInfo = result
                    self.isAnalyzing = false
                    self.navigateToConfirm = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.isAnalyzing = false
                }
            }
        }
    }
}
