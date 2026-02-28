import Foundation
import SwiftUI
import Combine

struct ExchangeRateResponse: Codable {
    let base: String
    let rates: [String: Double]
}

class CurrencyService: ObservableObject {
    private struct ExchangeRateCache: Codable {
        let base: String
        let rates: [String: Double]
        let fetchedAt: Date
    }
    
    @Published var rates: [String: Double] = [:]
    
    var mainCurrency: String {
        get { UserDefaults.standard.string(forKey: "mainCurrency") ?? "HKD" }
        set {
            UserDefaults.standard.set(newValue, forKey: "mainCurrency")
            loadRatesFromLocal()
        }
    }
    
    static let shared = CurrencyService()
    
    private let ratesCacheKey = "cachedExchangeRatesV2"
    private let legacyRatesKey = "cachedExchangeRates"
    private let cacheTTL: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    
    private init() {
        // 🔥 初始化時嘗試讀取本地緩存
        loadRatesFromLocal()
    }
    
    func fetchRates() async {
        let requestedBase = mainCurrency.uppercased()
        let urlString = "https://api.exchangerate-api.com/v4/latest/\(requestedBase)"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            
            await MainActor.run {
                // 避免主幣切換後，舊請求結果覆蓋新主幣資料
                guard requestedBase == self.mainCurrency.uppercased() else { return }
                
                self.rates = result.rates
                // 🔥 成功獲取後，儲存到本地
                self.saveRatesToLocal(base: requestedBase, rates: result.rates)
            }
        } catch {
            print("匯率獲取失敗: \(error)")
            // 失敗時，init 已經讀取了舊緩存，所以這裡不需要做什麼
        }
    }
    
    // MARK: - 緩存邏輯
    private func saveRatesToLocal(base: String, rates: [String: Double]) {
        let payload = ExchangeRateCache(base: base, rates: rates, fetchedAt: Date())
        if let encoded = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(encoded, forKey: ratesCacheKey)
        }
    }
    
    private func loadRatesFromLocal() {
        let currentBase = mainCurrency.uppercased()
        
        if let data = UserDefaults.standard.data(forKey: ratesCacheKey),
           let payload = try? JSONDecoder().decode(ExchangeRateCache.self, from: data) {
            guard payload.base.uppercased() == currentBase else {
                // base 不一致時忽略，避免錯用他幣快取
                self.rates = [:]
                print("⚠️ 忽略不匹配 base 的匯率快取: \(payload.base) -> \(currentBase)")
                return
            }
            
            let age = Date().timeIntervalSince(payload.fetchedAt)
            guard age <= cacheTTL else {
                self.rates = [:]
                print("⚠️ 匯率快取已過期，等待重新抓取")
                return
            }
            
            self.rates = payload.rates
            print("✅ 已載入本地匯率緩存 (\(payload.base))")
            return
        }
        
        // 舊版快取沒有 base 資訊，不能安全使用，避免錯算
        if UserDefaults.standard.data(forKey: legacyRatesKey) != nil {
            UserDefaults.standard.removeObject(forKey: legacyRatesKey)
            print("⚠️ 已清除舊版匯率快取（缺少 base 資訊）")
            self.rates = [:]
        }
    }
    
    func convert(amount: Decimal, from currency: String) -> Decimal {
        if currency == mainCurrency { return amount }
        guard let rate = rates[currency], rate.isFinite, rate > 0 else { return amount } // 避免異常匯率造成非有限數值
        return amount / Decimal(rate)
    }
    
    func convert(amount: Decimal, from source: String, to target: String) -> Decimal {
        if source == target { return amount }
        
        if source == mainCurrency {
            guard let targetRate = rates[target], targetRate.isFinite, targetRate > 0 else { return amount }
            return amount * Decimal(targetRate)
        }
        
        if target == mainCurrency {
            return convert(amount: amount, from: source)
        }
        
        guard let targetRate = rates[target], targetRate.isFinite, targetRate > 0 else { return amount }
        let inMain = convert(amount: amount, from: source)
        return inMain * Decimal(targetRate)
    }
    
    func getMarketRate(from source: String, to target: String) -> Double? {
        if source == target { return 1.0 }
        guard let rateSource = rates[source], let rateTarget = rates[target] else { return nil }
        return (1.0 / rateSource) * rateTarget
    }
}
