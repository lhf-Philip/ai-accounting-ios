import Foundation
import SwiftUI
import Combine

struct ExchangeRateResponse: Codable {
    let base: String
    let rates: [String: Double]
}

class CurrencyService: ObservableObject {
    @Published var rates: [String: Double] = [:]
    
    var mainCurrency: String {
        get { UserDefaults.standard.string(forKey: "mainCurrency") ?? "HKD" }
        set { UserDefaults.standard.set(newValue, forKey: "mainCurrency") }
    }
    
    static let shared = CurrencyService()
    
    private let ratesKey = "cachedExchangeRates"
    
    private init() {
        // 🔥 初始化時嘗試讀取本地緩存
        loadRatesFromLocal()
    }
    
    func fetchRates() async {
        let urlString = "https://api.exchangerate-api.com/v4/latest/\(mainCurrency)"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            DispatchQueue.main.async {
                self.rates = result.rates
                // 🔥 成功獲取後，儲存到本地
                self.saveRatesToLocal(result.rates)
            }
        } catch {
            print("匯率獲取失敗: \(error)")
            // 失敗時，init 已經讀取了舊緩存，所以這裡不需要做什麼
        }
    }
    
    // MARK: - 緩存邏輯
    private func saveRatesToLocal(_ rates: [String: Double]) {
        if let encoded = try? JSONEncoder().encode(rates) {
            UserDefaults.standard.set(encoded, forKey: ratesKey)
        }
    }
    
    private func loadRatesFromLocal() {
        if let data = UserDefaults.standard.data(forKey: ratesKey),
           let savedRates = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.rates = savedRates
            print("✅ 已載入本地匯率緩存")
        }
    }
    
    func convert(amount: Decimal, from currency: String) -> Decimal {
        if currency == mainCurrency { return amount }
        guard let rate = rates[currency] else { return amount } // 如果完全沒匯率，回傳原值
        return amount / Decimal(rate)
    }
    
    func getMarketRate(from source: String, to target: String) -> Double? {
        if source == target { return 1.0 }
        guard let rateSource = rates[source], let rateTarget = rates[target] else { return nil }
        return (1.0 / rateSource) * rateTarget
    }
}
