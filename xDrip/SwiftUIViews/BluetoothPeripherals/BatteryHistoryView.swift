//
//  BatteryHistoryView.swift
//  xdrip
//
//  Created by Paul Plant on 1/9/26.
//  Copyright © 2026 Johan Degraeve. All rights reserved.
//

import Charts
import CoreData
import SwiftUI

/// The time window displayed by the battery-history chart.
///
/// Fixed ranges always run backwards from the current time. Before a device reaches the next fixed
/// width, its actual recorded lifetime occupies that position so the picker never offers empty time.
enum BatteryHistoryRange: Hashable, Identifiable {
    case days(Int)
    case lifetime(TimeInterval)

    var id: String { label }
    var label: String {
        switch self {
        case .days(let days): return "\(days)\(Texts_Common.dayshort)"
        case .lifetime(let duration):
            let hours = max(1, Int(duration / 3600))
            return hours >= 24
                ? "\(hours / 24)\(Texts_Common.dayshort)\(hours % 24 == 0 ? "" : "\(hours % 24)\(Texts_Common.hourshort)")"
                : "\(hours)\(Texts_Common.hourshort)"
        }
    }

    static func available(firstObservation: Date, now: Date) -> [BatteryHistoryRange] {
        let lifetime = max(0, now.timeIntervalSince(firstObservation))
        var ranges = [BatteryHistoryRange]()
        for days in [3, 7, 12] where lifetime >= TimeInterval(days: Double(days)) {
            ranges.append(.days(days))
        }
        if ranges.isEmpty {
            ranges.append(.lifetime(lifetime))
        } else if lifetime < TimeInterval(days: 12),
                  case .days(let lastDays) = ranges.last,
                  lifetime > TimeInterval(days: Double(lastDays)) {
            // Below 12 days, the next unavailable fixed option is replaced by the actual lifetime.
            ranges.append(.lifetime(lifetime))
        } else if lifetime >= TimeInterval(days: 12) + 3600 {
            // Avoid showing a lifetime option that is effectively identical to the 12-day range.
            ranges.append(.lifetime(lifetime))
        }
        return ranges
    }

    func domain(now: Date) -> ClosedRange<Date> {
        let duration: TimeInterval
        switch self {
        case .days(let days): duration = TimeInterval(days: Double(days))
        case .lifetime(let lifetime): duration = max(6 * 3600, lifetime)
        }
        return now.addingTimeInterval(-duration) ... now
    }
}

/// Creates stable localized X-axis marks for the selected battery-history domain.
struct BatteryHistoryXAxis {
    let domain: ClosedRange<Date>
    let calendar: Calendar

    init(domain: ClosedRange<Date>, calendar: Calendar = .autoupdatingCurrent) {
        self.domain = domain
        self.calendar = calendar
    }

    var dates: [Date] {
        let component: Calendar.Component = usesHourlyMarks ? .hour : .day
        let firstBoundary: Date?

        if usesHourlyMarks {
            firstBoundary = calendar.dateInterval(of: .hour, for: domain.lowerBound)?.end
        } else {
            firstBoundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: domain.lowerBound))
        }

        var dates = [domain.lowerBound]
        var date = firstBoundary
        while let currentDate = date, currentDate < domain.upperBound {
            // The final endpoint labels its own hour or day, so omit a duplicate boundary label.
            if !calendar.isDate(currentDate, equalTo: domain.upperBound, toGranularity: component) {
                dates.append(currentDate)
            }
            date = calendar.date(byAdding: component, value: 1, to: currentDate)
        }
        dates.append(domain.upperBound)
        return dates
    }

    func label(for date: Date) -> String {
        usesHourlyMarks
            ? date.formatted(.dateTime.hour())
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    func labelAnchor(for date: Date) -> UnitPoint {
        if date == domain.lowerBound { return .topLeading }
        if date == domain.upperBound { return .topTrailing }
        return .top
    }

    private var usesHourlyMarks: Bool {
        domain.upperBound.timeIntervalSince(domain.lowerBound) <= TimeInterval(days: 1)
    }
}

/// Displays device information and genuine persisted battery observations for one saved peripheral.
struct BatteryHistoryView: View {
    let peripheralObjectID: NSManagedObjectID
    let manager: BatteryHistoryManager

    @State private var points = [BatteryHistoryPoint]()
    @State private var information: BatteryHistoryInformation?
    @State private var selectedRange: BatteryHistoryRange?
    @State private var selectedPoint: BatteryHistoryPoint?
    @State private var now = Date()

    // MARK: - view

    var body: some View {
        GeometryReader { geometry in
            List {
                if let information {
                    Section {
                        LabeledContent(Texts_BluetoothPeripheralView.batteryHistoryTransmitterID, value: information.bluetoothName)
                        if let reading = information.currentReading {
                            LabeledContent(Texts_BluetoothPeripheralView.battery, value: currentReadingText(reading, elapsed: information.transmitterLifetime))
                        }
                    } header: {
                        Text(information.transmitterDescription)
                    }
                }

                Section {
                    if points.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "battery.0percent")
                                .font(.largeTitle)
                            Text(Texts_BluetoothPeripheralView.batteryHistoryNoData)
                                .font(.headline)
                            Text(Texts_BluetoothPeripheralView.batteryHistoryBeginsAfterReading)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    } else {
                        batteryHistoryChart(availableHeight: geometry.size.height)
                            .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                    }
                } header: {
                    Text(Texts_BluetoothPeripheralView.batteryHistory)
                    if !points.isEmpty {
                        Text(Texts_BluetoothPeripheralView.batteryHistoryRangeExplanation)
                    }
                }
            }
        }
        .navigationTitle(Texts_BluetoothPeripheralView.batteryHistory)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(ConstantsUI.listBackGroundColor)
        .colorScheme(.dark)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .batteryHistoryDidChange)) { note in
            guard note.object as? NSManagedObjectID == peripheralObjectID else { return }
            reload()
        }
    }

    private var availableRanges: [BatteryHistoryRange] {
        guard let first = points.first?.observedAt else { return [] }
        return BatteryHistoryRange.available(firstObservation: first, now: now)
    }

    private func batteryHistoryChart(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let activeChartPoint {
                HStack(alignment: .firstTextBaseline) {
                    Text(activeChartPoint.observedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(Color(.colorSecondary))

                    Spacer(minLength: 8)

                    batteryValuePill(for: activeChartPoint)
                }
                .font(.subheadline.monospacedDigit())
            }

            chart
                .frame(height: chartHeight(availableHeight: availableHeight))
                .padding(.top, 2)

            Picker(
                Texts_BluetoothPeripheralView.batteryHistoryRange,
                selection: Binding(
                    get: { effectiveRange },
                    set: {
                        selectedRange = $0
                        selectedPoint = nil
                    }
                )
            ) {
                ForEach(availableRanges) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Texts_BluetoothPeripheralView.batteryHistoryRangeAccessibility)
        }
    }

    @ViewBuilder private func batteryValuePill(for point: BatteryHistoryPoint) -> some View {
        if let reading = batteryReading(for: point) {
            HStack(spacing: 4) {
                Text(Texts_BluetoothPeripheralView.battery + ":")
                    .foregroundStyle(Color(.colorSecondary))
                Text(currentReadingValueText(reading))
                    .foregroundStyle(Color.cyan)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(.systemGray6), in: Capsule())
            .accessibilityLabel(Texts_BluetoothPeripheralView.battery + " " + currentReadingValueText(reading))
        }
    }

    private func chartHeight(availableHeight: CGFloat) -> CGFloat {
        min(220, max(150, (availableHeight - 400) * 0.55))
    }

    private func lifetimeText(_ lifetime: TimeInterval) -> String {
        (lifetime / 60).minutesToDaysAndHours()
    }


    private func currentReadingText(_ reading: BatteryHistoryCurrentReading, elapsed: TimeInterval?) -> String {
        let value = currentReadingValueText(reading)
        guard let elapsed else { return value }
        return "\(value) (\(lifetimeText(elapsed)))"
    }

    private func currentReadingValueText(_ reading: BatteryHistoryCurrentReading) -> String {
        switch reading {
        case .percentage(let value): return "\(value)%"
        case .voltageB(let rawValue): return "\(rawValue * 10)mV"
        }
    }

    private func batteryReading(for point: BatteryHistoryPoint) -> BatteryHistoryCurrentReading? {
        switch point.kind {
        case .percentage:
            return point.percentage.map(BatteryHistoryCurrentReading.percentage)
        case .dexcomVoltage:
            return point.voltageB.map { .voltageB(rawValue: $0) }
        }
    }

    private var effectiveRange: BatteryHistoryRange {
        if let selectedRange, availableRanges.contains(selectedRange) { return selectedRange }
        return availableRanges.last ?? .lifetime(0)
    }

    private var visiblePoints: [BatteryHistoryPoint] {
        let domain = effectiveRange.domain(now: now)
        return points.filter { domain.contains($0.observedAt) }
    }

    private var dominantVisiblePoints: [BatteryHistoryPoint] {
        let usesPercentage = points.last?.kind == .percentage
        return visiblePoints.filter {
            usesPercentage ? $0.percentage != nil : $0.voltageB != nil
        }
    }

    private var activeChartPoint: BatteryHistoryPoint? {
        // Match the noise-history interaction: show the latest point until the user touches a value.
        if let selectedPoint, dominantVisiblePoints.contains(where: { $0.id == selectedPoint.id }) {
            return selectedPoint
        }
        return dominantVisiblePoints.last
    }

    private func nearestVisiblePoint(to date: Date) -> BatteryHistoryPoint? {
        dominantVisiblePoints.min {
            abs($0.observedAt.timeIntervalSince(date)) < abs($1.observedAt.timeIntervalSince(date))
        }
    }

    @ViewBuilder private var chart: some View {
        let domain = effectiveRange.domain(now: now)
        let xAxis = BatteryHistoryXAxis(domain: domain)
        let latest = points.last
        let isPercentage = latest?.kind == .percentage
        let family = latest?.family
        let percentagePoints = visiblePoints.filter { $0.percentage != nil }
        let voltageBPoints = visiblePoints.filter { $0.voltageB != nil }
        let activePoint = activeChartPoint

        Chart {
            if isPercentage {
                // Percentage bands reuse the same urgent and warning boundaries as the
                // Bluetooth battery symbol shown in the peripheral detail section.
                RectangleMark(
                    xStart: .value("Start", domain.lowerBound),
                    xEnd: .value("End", domain.upperBound),
                    yStart: .value("Urgent", 0),
                    yEnd: .value("Urgent threshold", BluetoothBatteryLevelPresentation.urgentUpperBound)
                )
                .foregroundStyle(Color.red.opacity(0.06))
                RectangleMark(
                    xStart: .value("Start", domain.lowerBound),
                    xEnd: .value("End", domain.upperBound),
                    yStart: .value("Warning", BluetoothBatteryLevelPresentation.urgentUpperBound),
                    yEnd: .value("Healthy", BluetoothBatteryLevelPresentation.warningUpperBound)
                )
                .foregroundStyle(Color.yellow.opacity(0.055))
                ForEach(BluetoothBatteryLevelPresentation.chartThresholds, id: \.self) { threshold in
                    RuleMark(y: .value("Threshold", threshold))
                        .foregroundStyle(Color(.systemGray2).opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                }

                ForEach(segmentedPoints(percentagePoints, maximumGap: 2 * 3600)) { item in
                    LineMark(x: .value("Time", item.point.observedAt), y: .value("Battery", item.point.percentage!), series: .value("Series", "Percentage-\(item.segment)"))
                        .foregroundStyle(Color.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            } else {
                if let family {
                    RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound), yStart: .value("Low", 0), yEnd: .value("Low threshold", family.redBelow * 10))
                        .foregroundStyle(Color.red.opacity(0.06))
                    RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound), yStart: .value("Caution", family.redBelow * 10), yEnd: .value("Healthy", family.greenFrom * 10))
                        .foregroundStyle(Color.yellow.opacity(0.055))
                    ForEach([family.redBelow, family.greenFrom], id: \.self) { threshold in
                        RuleMark(y: .value("Threshold", threshold * 10))
                            .foregroundStyle(Color(.systemGray2).opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                    }
                }
                ForEach(segmentedPoints(visiblePoints.filter { $0.voltageA != nil }, maximumGap: 4 * 3600)) { item in
                    LineMark(x: .value("Time", item.point.observedAt), y: .value("Voltage A", item.point.voltageA! * 10), series: .value("Series", "A-\(item.segment)"))
                        .foregroundStyle(Color(.systemGray2).opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                ForEach(segmentedPoints(voltageBPoints, maximumGap: 4 * 3600)) { item in
                    LineMark(x: .value("Time", item.point.observedAt), y: .value("Voltage B", item.point.voltageB! * 10), series: .value("Series", "B-\(item.segment)"))
                        .foregroundStyle(Color.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }

            if let activePoint {
                RuleMark(x: .value("Selected time", activePoint.observedAt))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.65))

                if isPercentage, let percentage = activePoint.percentage {
                    PointMark(x: .value("Selected time", activePoint.observedAt), y: .value("Battery", percentage))
                        .foregroundStyle(Color.cyan)
                        .symbolSize(48)
                } else if let voltageB = activePoint.voltageB {
                    PointMark(x: .value("Selected time", activePoint.observedAt), y: .value("Voltage B", voltageB * 10))
                        .foregroundStyle(Color.cyan)
                        .symbolSize(48)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: isPercentage ? 0 ... 100 : automaticVoltageDomain)
        .chartXAxis {
            AxisMarks(values: xAxis.dates) { value in
                AxisGridLine()
                    .foregroundStyle(Color(.systemGray3).opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color(.systemGray2))
                AxisValueLabel(anchor: value.as(Date.self).map(xAxis.labelAnchor)) {
                    if let date = value.as(Date.self) {
                        Text(xAxis.label(for: date))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(.colorSecondary))
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartOverlay { chartProxy in
            GeometryReader { geometryProxy in
                // A zero-distance drag supports both a tap and a continuous scrub over real samples.
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let plotFrame = geometryProxy[chartProxy.plotAreaFrame]
                                let xPosition = gesture.location.x - plotFrame.origin.x

                                guard xPosition >= 0,
                                      xPosition <= plotFrame.width,
                                      let date: Date = chartProxy.value(atX: xPosition) else { return }

                                selectedPoint = nearestVisiblePoint(to: date)
                            }
                    )
            }
        }
        .accessibilityLabel(Texts_BluetoothPeripheralView.batteryHistory)
    }

    private struct SegmentedPoint: Identifiable {
        let point: BatteryHistoryPoint
        let segment: Int
        var id: String { point.id }
    }

    private func segmentedPoints(_ source: [BatteryHistoryPoint], maximumGap: TimeInterval) -> [SegmentedPoint] {
        // A new series prevents Charts from drawing an invented line through a missing-reading gap.
        var segment = 0
        var previousDate: Date?
        return source.map { point in
            if let previousDate, point.observedAt.timeIntervalSince(previousDate) > maximumGap { segment += 1 }
            previousDate = point.observedAt
            return SegmentedPoint(point: point, segment: segment)
        }
    }

    private var automaticVoltageDomain: ClosedRange<Int> {
        let values = visiblePoints.flatMap { [$0.voltageA, $0.voltageB].compactMap { $0 }.map { $0 * 10 } }
        guard let minimum = values.min(), let maximum = values.max() else { return 0 ... 3000 }
        let padding = max(50, (maximum - minimum) / 5)
        return max(0, minimum - padding) ... (maximum + padding)
    }

    private func reload() {
        now = Date()
        points = manager.history(peripheralObjectID: peripheralObjectID)
        selectedPoint = nil
        information = manager.information(peripheralObjectID: peripheralObjectID, now: now)
        if selectedRange == nil { selectedRange = availableRanges.last }
    }
}
