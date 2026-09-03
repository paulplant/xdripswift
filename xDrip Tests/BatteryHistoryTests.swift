//
//  BatteryHistoryTests.swift
//  xdripTests
//
//  Created by Paul Plant on 1/9/26.
//  Copyright © 2026 Johan Degraeve. All rights reserved.
//

import XCTest
@testable import xdrip

final class BatteryHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAdaptiveRangesReplaceNextUnavailableFixedRangeWithLifetime() {
        XCTAssertEqual(labels(afterDays: 2), ["2d"])
        XCTAssertEqual(labels(afterDays: 3), ["3d"])
        XCTAssertEqual(labels(afterDays: 5), ["3d", "5d"])
        XCTAssertEqual(labels(afterDays: 7), ["3d", "7d"])
        XCTAssertEqual(labels(afterDays: 10), ["3d", "7d", "10d"])
        XCTAssertEqual(labels(afterDays: 12), ["3d", "7d", "12d"])
    }

    func testLifetimeBeyondTwelveDaysRequiresOneHourOfAdditionalWidth() {
        XCTAssertEqual(labels(after: TimeInterval(days: 12) + 3599), ["3d", "7d", "12d"])
        XCTAssertEqual(labels(after: TimeInterval(days: 12) + 3600), ["3d", "7d", "12d", "12d1h"])
    }

    func testAdaptiveRangeIdentityDoesNotCollideWithTruncatedLifetimeLabel() {
        for lifetime in [
            TimeInterval(days: 3) + 1,
            TimeInterval(days: 3) + 3599,
            TimeInterval(days: 7) + 1,
            TimeInterval(days: 7) + 3599,
        ] {
            let ranges = BatteryHistoryRange.available(
                firstObservation: now.addingTimeInterval(-lifetime),
                now: now
            )

            XCTAssertEqual(Set(ranges.map(\.id)).count, ranges.count)
        }
    }

    func testLifetimeChartHasSixHourMinimumDomain() {
        let range = BatteryHistoryRange.lifetime(30 * 60).domain(now: now)
        XCTAssertEqual(range.upperBound.timeIntervalSince(range.lowerBound), 6 * 3600, accuracy: 0.001)
    }

    func testHourlyXAxisIncludesBothEndpointsAndOneMarkForEachIntermediateHour() {
        let start = utcDate(year: 2026, month: 9, day: 1, hour: 12, minute: 30)
        let end = utcDate(year: 2026, month: 9, day: 2, hour: 12, minute: 30)
        let axis = BatteryHistoryXAxis(domain: start ... end, calendar: utcCalendar)

        XCTAssertEqual(axis.dates.first, start)
        XCTAssertEqual(axis.dates.last, end)
        XCTAssertEqual(axis.dates.count, 25)
        XCTAssertEqual(axis.dates.dropFirst().dropLast().map { utcCalendar.component(.minute, from: $0) }, Array(repeating: 0, count: 23))
    }

    func testDailyXAxisIncludesOneMarkForEveryDisplayedCalendarDay() {
        let start = utcDate(year: 2026, month: 9, day: 1, hour: 12, minute: 30)
        let end = utcDate(year: 2026, month: 9, day: 4, hour: 12, minute: 30)
        let axis = BatteryHistoryXAxis(domain: start ... end, calendar: utcCalendar)

        XCTAssertEqual(axis.dates.first, start)
        XCTAssertEqual(axis.dates.last, end)
        XCTAssertEqual(axis.dates.map { utcCalendar.component(.day, from: $0) }, [1, 2, 3, 4])
    }

    func testXAxisLabelsOnlyFirstAndLastMarks() {
        let start = utcDate(year: 2026, month: 9, day: 1, hour: 12, minute: 30)
        let end = utcDate(year: 2026, month: 9, day: 2, hour: 12, minute: 30)
        let axis = BatteryHistoryXAxis(domain: start ... end, calendar: utcCalendar)

        XCTAssertTrue(axis.isEndpoint(start))
        XCTAssertTrue(axis.isEndpoint(end))
        XCTAssertTrue(axis.dates.dropFirst().dropLast().allSatisfy { !axis.isEndpoint($0) })
    }

    func testStandardBatteryParserAcceptsZeroAndRejectsMalformedValues() {
        XCTAssertEqual(StandardBluetoothBatteryLevel.percentage(from: Data([0])), 0)
        XCTAssertEqual(StandardBluetoothBatteryLevel.percentage(from: Data([100])), 100)
        XCTAssertNil(StandardBluetoothBatteryLevel.percentage(from: Data([101])))
        XCTAssertNil(StandardBluetoothBatteryLevel.percentage(from: Data([50, 51])))
        XCTAssertNil(StandardBluetoothBatteryLevel.percentage(from: nil))
    }

    func testPercentageThresholdsMatchBluetoothBatteryPresentation() {
        XCTAssertEqual(BluetoothBatteryLevelPresentation.urgentUpperBound, 10)
        XCTAssertEqual(BluetoothBatteryLevelPresentation.warningUpperBound, 25)
        XCTAssertEqual(BluetoothBatteryLevelPresentation.chartThresholds, [10, 25])
    }

    func testDexcomThresholdsRemainFamilySpecific() {
        XCTAssertEqual(DexcomBatteryFamily.g5.redBelow, 270)
        XCTAssertEqual(DexcomBatteryFamily.g5.greenFrom, 280)
        XCTAssertEqual(DexcomBatteryFamily.g7.redBelow, 215)
        XCTAssertEqual(DexcomBatteryFamily.g7.greenFrom, 250)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func labels(afterDays days: Double) -> [String] {
        labels(after: TimeInterval(days: days))
    }

    private func labels(after lifetime: TimeInterval) -> [String] {
        BatteryHistoryRange.available(firstObservation: now.addingTimeInterval(-lifetime), now: now).map(\.label)
    }
}
