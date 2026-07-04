import Foundation
import XCTest

func exactDecimal(
    _ value: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Decimal {
    guard let decimal = Decimal(string: value) else {
        XCTFail("Invalid exact decimal fixture: \(value)", file: file, line: line)
        return .zero
    }
    return decimal
}
