import Foundation
import UIKit
import GoogleGenerativeAI

struct ReceiptInfo: Codable {
    let amount: Decimal
    let currency: String
    let date: String
    let merchant: String
    let categoryName: String
    let note: String
}

class GeminiService {
    static let shared = GeminiService()
    private let keychainServiceName = "org.duckdns.lhfser.AIMoney"
    private let keychainAccountName = "gemini_api_key"
    private let legacyUserDefaultsKey = "UserGeminiAPIKey"
    
    private var apiKey: String {
        if let keychainValue = KeychainService.shared.read(service: keychainServiceName, account: keychainAccountName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !keychainValue.isEmpty {
            return keychainValue
        }
        
        let legacyValue = (UserDefaults.standard.string(forKey: legacyUserDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !legacyValue.isEmpty {
            _ = KeychainService.shared.save(service: keychainServiceName, account: keychainAccountName, value: legacyValue)
            UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            return legacyValue
        }
        
        return ""
    }
    
    // 🔥 最終答案：根據你的列表，選用最標準的 2.0 Flash
    private let modelName = "gemini-flash-latest"
    
    private init() {}
    
    func analyzeReceipt(image: UIImage, userNote: String) async throws -> ReceiptInfo {
        // 1. 檢查 Key
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Gemini", code: 401, userInfo: [NSLocalizedDescriptionKey: "未設定 API Key。"])
        }
        
        // 2. 初始化模型
        let model = GenerativeModel(name: modelName, apiKey: apiKey)
        
        // 3. 壓縮圖片
        guard let processedImage = image.resized(to: 1024) else {
            throw URLError(.badURL)
        }
        
        // 4. Prompt 設定
        let prompt = """
        You are an AI assistant for a personal finance app. 
        Analyze the attached receipt image and the user's specific instruction: "\(userNote)".
        
        Task:
        1. Identify the Merchant Name. (Translate to Traditional Chinese 繁體中文 if possible).
        2. Identify the Date (Format: YYYY-MM-DD). If year is missing, assume current year.
        3. Calculate the Total Amount relevant to the user. 
           - IF the user note says "split bill" or specific items, ONLY sum up those items.
           - IF the user note is empty, take the receipt grand total.
        4. Suggest a Category (e.g., 餐飲, 交通, 購物, 娛樂, 超市, 醫療, 薪水).
        5. Currency: Try to detect currency code (HKD, USD, TWD, JPY, CNY), default to HKD if unknown.
        6. Note: Summarize what was bought or the user's note.
        
        IMPORTANT LANGUAGE REQUIREMENT:
        - The fields 'merchant', 'categoryName', and 'note' MUST be in Traditional Chinese (繁體中文).
        - Even if the receipt is in English or Japanese, translate the description to Traditional Chinese.
        
        Output MUST be strict JSON format without Markdown code blocks (```json).
        
        JSON Structure Example:
        {
            "amount": 100.5,
            "currency": "HKD",
            "date": "2024-01-01",
            "merchant": "麥當勞",
            "categoryName": "餐飲",
            "note": "午餐"
        }
        """
        
        // 5. 發送請求
        do {
            print("🚀 使用模型 \(modelName) 發送請求中...")
            let response = try await model.generateContent(prompt, processedImage)
            print("✅ 收到回應")
            
            guard let text = response.text else {
                throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI 未回傳文字結果"])
            }
            
            let cleanText = text.replacingOccurrences(of: "```json", with: "")
                                .replacingOccurrences(of: "```", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = cleanText.data(using: .utf8) else {
                throw NSError(domain: "Gemini", code: -2, userInfo: [NSLocalizedDescriptionKey: "AI 回傳格式錯誤"])
            }
            
            return try JSONDecoder().decode(ReceiptInfo.self, from: data)
            
        } catch let error {
            print("❌ Gemini Error: \(error.localizedDescription)")
            
            let errorStr = String(describing: error)
            
            if errorStr.contains("429") {
                throw NSError(domain: "Gemini", code: 429, userInfo: [NSLocalizedDescriptionKey: "免費額度已用完 (429)。"])
            } else if errorStr.contains("404") {
                throw NSError(domain: "Gemini", code: 404, userInfo: [NSLocalizedDescriptionKey: "模型 404。請檢查模型名稱是否在可用列表中。"])
            }
            
            throw error
        }
    }
}

extension UIImage {
    func resized(to maxDimension: CGFloat) -> UIImage? {
        let aspectRatio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
}
