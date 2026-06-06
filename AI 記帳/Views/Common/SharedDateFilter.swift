import Foundation

enum DateFilterPreferenceKeys {
    static let filterType = "sharedDateFilterType"
    static let selectedDate = "sharedDateFilterSelectedDate"
    static let customStartDate = "sharedDateFilterCustomStartDate"
    static let customEndDate = "sharedDateFilterCustomEndDate"
}

extension FilterType {
    func dateInterval(
        selectedDate: Date,
        customStartDate: Date,
        customEndDate: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case .year:
            return calendar.dateInterval(of: .year, for: selectedDate)
        case .month:
            return calendar.dateInterval(of: .month, for: selectedDate)
        case .day:
            return calendar.dateInterval(of: .day, for: selectedDate)
        case .custom:
            let range = normalizedCustomRange(start: customStartDate, end: customEndDate)
            let start = calendar.startOfDay(for: range.start)
            let end = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: range.end)
            ) ?? range.end
            return DateInterval(start: start, end: end)
        }
    }

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
        guard let interval = dateInterval(
            selectedDate: selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            calendar: calendar
        ) else {
            return true
        }
        return date >= interval.start && date < interval.end
    }
}

func normalizedCustomRange(start: Date, end: Date) -> (start: Date, end: Date) {
    start <= end ? (start, end) : (end, start)
}
