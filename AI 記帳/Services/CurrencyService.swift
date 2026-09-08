import Foundation
import SwiftUI
import Combine

struct ExchangeRateResponse: Codable {
    let base: String
    let rates: [String: Double]
}

struct CurrencyConversionEstimate {
    let amount: Decimal
    let source: RateSourceState
}

class CurrencyService: ObservableObject {
    private let defaults: UserDefaults
    private let now: () -> Date
    private struct ExchangeRateCache: Codable {
        let base: String
        let rates: [String: Double]
        let fetchedAt: Date
    }
    
    @Published var rates: [String: Double] = [:]
    @Published private(set) var rateSourceState: RateSourceState = .unavailable
    private var staleRates: [String: Double] = [:]
    
    var mainCurrency: String {
        get { defaults.string(forKey: "mainCurrency") ?? "HKD" }
        set {
            defaults.set(newValue.uppercased(), forKey: "mainCurrency")
            loadRatesFromLocal()
        }
    }
    
    static let shared = CurrencyService(defaults: .standard)
    
    private let ratesCacheKey = "cachedExchangeRatesV2"
    private let legacyRatesKey = "cachedExchangeRates"
    private let cacheTTL: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    
    init(defaults: UserDefaults, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
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
        let payload = ExchangeRateCache(base: base, rates: rates, fetchedAt: now())
        if let encoded = try? JSONEncoder().encode(payload) {
            defaults.set(encoded, forKey: ratesCacheKey)
        }
    }
    
    private func loadRatesFromLocal() {
        let currentBase = mainCurrency.uppercased()
        self.rates = [:]
        self.staleRates = [:]
        self.rateSourceState = .unavailable
        
        if let data = defaults.data(forKey: ratesCacheKey),
           let payload = try? JSONDecoder().decode(ExchangeRateCache.self, from: data) {
            guard payload.base.uppercased() == currentBase else {
                // base 不一致時忽略，避免錯用他幣快取
                print("⚠️ 忽略不匹配 base 的匯率快取: \(payload.base) -> \(currentBase)")
                return
            }
            
            self.staleRates = payload.rates
            let age = now().timeIntervalSince(payload.fetchedAt)
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
        if defaults.data(forKey: legacyRatesKey) != nil {
            defaults.removeObject(forKey: legacyRatesKey)
            print("⚠️ 已清除舊版匯率快取（缺少 base 資訊）")
        }
    }
    
    func convert(amount: Decimal, from currency: String) throws -> Decimal {
        try convert(amount: amount, from: currency, to: mainCurrency)
    }

    func convert(amount: Decimal, from source: String, to target: String) throws -> Decimal {
        guard let result = estimate(amount: amount, from: source, to: target), !result.amount.isNaN else {
            throw CurrencyConversionError.unavailable(source.uppercased(), target.uppercased())
        }
        return result.amount
    }

    func totalEstimate(_ amounts: [(amount: Decimal, currencyCode: String)], to target: String? = nil) -> CurrencyTotalEstimate {
        let target = target ?? mainCurrency
        var total = Decimal.zero
        var status = ReportEstimateStatus.exact
        var available = 0
        var unavailable = 0
        for item in amounts {
            guard let value = estimate(amount: item.amount, from: item.currencyCode, to: target), !value.amount.isNaN else {
                unavailable += 1
                continue
            }
            total += value.amount
            available += 1
            if item.currencyCode.uppercased() != target.uppercased() {
                if value.source == .cached { status = .cached }
                else if status == .exact { status = .live }
            }
        }
        if unavailable > 0 || total.isNaN {
            return CurrencyTotalEstimate(amount: nil, status: available > 0 ? .partial : .unavailable)
        }
        return CurrencyTotalEstimate(amount: total, status: status)
    }

    func estimate(amount: Decimal, from source: String, to target: String) -> CurrencyConversionEstimate? {
        guard !amount.isNaN else { return nil }
        let sourceCode = source.uppercased()
        let targetCode = target.uppercased()
        if sourceCode == targetCode {
            return CurrencyConversionEstimate(amount: amount, source: resolvedRateSourceState)
        }

        let converted: Decimal
        if sourceCode == mainCurrency.uppercased() {
            guard let rate = usableRate(for: targetCode) else { return nil }
            converted = amount * rate
        } else if targetCode == mainCurrency.uppercased() {
            guard let rate = usableRate(for: sourceCode) else { return nil }
            converted = amount / rate
        } else {
            guard let sourceRate = usableRate(for: sourceCode), let targetRate = usableRate(for: targetCode) else { return nil }
            converted = amount / sourceRate * targetRate
        }
        guard !converted.isNaN else { return nil }
        return CurrencyConversionEstimate(amount: converted, source: resolvedRateSourceState)
    }

    private func usableRate(for code: String) -> Decimal? {
        guard let value = resolvedRates[code], value.isFinite, value > 0,
              let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN, decimal > 0 else { return nil }
        return decimal
    }

    func getMarketRate(from source: String, to target: String) -> Double? {
        guard let estimate = estimate(amount: 1, from: source, to: target) else { return nil }
        let rate = NSDecimalNumber(decimal: estimate.amount).doubleValue
        return rate.isFinite && rate > 0 ? rate : nil
    }

    func previewInMainCurrency(amount: Decimal, from currency: String) -> (amount: Decimal, source: RateSourceState)? {
        guard currency.uppercased() != mainCurrency.uppercased() else { return nil }
        guard let estimate = estimate(amount: amount, from: currency.uppercased(), to: mainCurrency) else { return nil }
        return (estimate.amount, estimate.source)
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


enum CurrencyConversionError: LocalizedError {
    case unavailable(String, String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let source, let target):
            return String(localized: "無法換算 \(source) 至 \(target)：缺少有效匯率。請更新匯率後重試。")
        }
    }
}

struct CurrencyTotalEstimate {
    let amount: Decimal?
    let status: ReportEstimateStatus

    func formatted(in currency: String) -> String {
        guard let amount else { return String(localized: "無法估算（缺少匯率）") }
        let value = amount.formatted(.currency(code: currency))
        guard let label = status.label else { return value }
        return "\(value) · \(label)"
    }
}
