import SwiftUI

struct CurrencyRateHintView: View {
    @ObservedObject var currencyService: CurrencyService
    let amount: Decimal?
    let currencyCode: String

    var body: some View {
        if let amount,
           let preview = currencyService.previewInMainCurrency(amount: amount, from: currencyCode) {
            VStack(alignment: .leading, spacing: 4) {
                Text("約 \(preview.amount.formatted(.currency(code: currencyService.mainCurrency)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preview.source.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if currencyCode.uppercased() != currencyService.mainCurrency.uppercased() {
            Text("暫時無法取得匯率")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TransferRateHintView: View {
    @ObservedObject var currencyService: CurrencyService
    let outgoingAmount: Decimal?
    let outgoingCurrency: String
    let incomingAmount: Decimal?
    let incomingCurrency: String

    private var inferredRateText: String? {
        guard let outgoingAmount, let incomingAmount,
              outgoingAmount > 0, incomingAmount > 0,
              outgoingCurrency.uppercased() != incomingCurrency.uppercased() else { return nil }
        let impliedRate = NSDecimalNumber(decimal: incomingAmount / outgoingAmount).doubleValue
        guard impliedRate.isFinite, impliedRate > 0 else { return nil }
        return String(format: "輸入匯率：1 %@ = %.4f %@", outgoingCurrency.uppercased(), impliedRate, incomingCurrency.uppercased())
    }

    private var marketRateText: String? {
        guard outgoingCurrency.uppercased() != incomingCurrency.uppercased(),
              let rate = currencyService.getMarketRate(from: outgoingCurrency, to: incomingCurrency) else {
            return nil
        }
        return String(format: "參考匯率：1 %@ = %.4f %@（%@）", outgoingCurrency.uppercased(), rate, incomingCurrency.uppercased(), currencyService.resolvedRateSourceState.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let inferredRateText {
                Text(inferredRateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let marketRateText {
                Text(marketRateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if outgoingCurrency.uppercased() != incomingCurrency.uppercased() {
                Text("暫時無法取得匯率")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            CurrencyRateHintView(currencyService: currencyService, amount: outgoingAmount, currencyCode: outgoingCurrency)
            CurrencyRateHintView(currencyService: currencyService, amount: incomingAmount, currencyCode: incomingCurrency)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
