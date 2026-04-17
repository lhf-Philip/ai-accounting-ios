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
    @Published private(set) var rateSourceState: RateSourceState = .unavailable
    private var staleRates: [String: Double] = [:]
    
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
                self.staleRates = result.rates
                self.rateSourceState = .live
                // 🔥 成功獲取後，儲存到本地
                self.saveRatesToLocal(base: requestedBase, rates: result.rates)
            }
        } catch {
            print("匯率獲取失敗: \(error)")
            await MainActor.run {
                if requestedBase == self.mainCurrency.uppercased(), !self.staleRates.isEmpty {
                    self.rateSourceState = .cached
                } else {
                    self.rateSourceState = .unavailable
                }
            }
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
        self.rates = [:]
        self.staleRates = [:]
        self.rateSourceState = .unavailable
        
        if let data = UserDefaults.standard.data(forKey: ratesCacheKey),
           let payload = try? JSONDecoder().decode(ExchangeRateCache.self, from: data) {
            guard payload.base.uppercased() == currentBase else {
                // base 不一致時忽略，避免錯用他幣快取
                print("⚠️ 忽略不匹配 base 的匯率快取: \(payload.base) -> \(currentBase)")
                return
            }
            
            self.staleRates = payload.rates
            let age = Date().timeIntervalSince(payload.fetchedAt)
            if age > cacheTTL {
                self.rateSourceState = payload.rates.isEmpty ? .unavailable : .cached
                print("⚠️ 匯率快取已過期，等待重新抓取")
                return
            }
            
            self.rates = payload.rates
            self.rateSourceState = .cached
            print("✅ 已載入本地匯率緩存 (\(payload.base))")
            return
        }
        
        // 舊版快取沒有 base 資訊，不能安全使用，避免錯算
        if UserDefaults.standard.data(forKey: legacyRatesKey) != nil {
            UserDefaults.standard.removeObject(forKey: legacyRatesKey)
            print("⚠️ 已清除舊版匯率快取（缺少 base 資訊）")
        }
    }
    
    func convert(amount: Decimal, from currency: String) -> Decimal {
        if currency == mainCurrency { return amount }
        guard let rate = resolvedRates[currency.uppercased()], rate.isFinite, rate > 0 else { return amount } // 避免異常匯率造成非有限數值
        return amount / Decimal(rate)
    }
    
    func convert(amount: Decimal, from source: String, to target: String) -> Decimal {
        if source == target { return amount }
        
        if source == mainCurrency {
            guard let targetRate = resolvedRates[target.uppercased()], targetRate.isFinite, targetRate > 0 else { return amount }
            return amount * Decimal(targetRate)
        }
        
        if target == mainCurrency {
            return convert(amount: amount, from: source)
        }
        
        guard let targetRate = resolvedRates[target.uppercased()], targetRate.isFinite, targetRate > 0 else { return amount }
        let inMain = convert(amount: amount, from: source)
        return inMain * Decimal(targetRate)
    }
    
    func getMarketRate(from source: String, to target: String) -> Double? {
        if source == target { return 1.0 }
        guard let rateSource = resolvedRates[source.uppercased()], let rateTarget = resolvedRates[target.uppercased()] else { return nil }
        return (1.0 / rateSource) * rateTarget
    }

    func previewInMainCurrency(amount: Decimal, from currency: String) -> (amount: Decimal, source: RateSourceState)? {
        guard currency.uppercased() != mainCurrency.uppercased() else { return nil }
        guard !resolvedRates.isEmpty else { return nil }
        return (convert(amount: amount, from: currency.uppercased()), resolvedRateSourceState)
    }

    var resolvedRateSourceState: RateSourceState {
        if !rates.isEmpty { return rateSourceState }
        if !staleRates.isEmpty { return .cached }
        return .unavailable
    }

    private var resolvedRates: [String: Double] {
        rates.isEmpty ? staleRates : rates
    }
}
