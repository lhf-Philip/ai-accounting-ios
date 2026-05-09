import Foundation

enum DateFilterPreferenceKeys {
    static let filterType = "sharedDateFilterType"
    static let selectedDate = "sharedDateFilterSelectedDate"
    static let customStartDate = "sharedDateFilterCustomStartDate"
    static let customEndDate = "sharedDateFilterCustomEndDate"
}

extension FilterType {
    func displayString(
        selectedDate: Date,
        customStartDate: Date,
        customEndDate: Date,
        allTitle: String
    ) -> String {
        let formatter = DateFormatter()
        switch self {
        case .all:
            return allTitle
        case .year:
            return "\(Calendar.current.component(.year, from: selectedDate))年"
        case .month:
            formatter.dateFormat = "yyyy年 M月"
            return formatter.string(from: selectedDate)
        case .day:
            formatter.dateFormat = "M月d日"
            return formatter.string(from: selectedDate)
        case .custom:
            formatter.dateFormat = "yyyy-MM-dd"
            let range = normalizedCustomRange(start: customStartDate, end: customEndDate)
            return "\(formatter.string(from: range.start)) ~ \(formatter.string(from: range.end))"
        }
    }

    func matches(
        date: Date,
        selectedDate: Date,
        customStartDate: Date,
        customEndDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .year:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .year)
        case .month:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
        case .day:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .day)
        case .custom:
            let range = normalizedCustomRange(start: customStartDate, end: customEndDate)
            let startOfDay = calendar.startOfDay(for: range.start)
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: range.end)) ?? range.end
            return date >= startOfDay && date < exclusiveEnd
        }
    }
}

func normalizedCustomRange(start: Date, end: Date) -> (start: Date, end: Date) {
    start <= end ? (start, end) : (end, start)
}
