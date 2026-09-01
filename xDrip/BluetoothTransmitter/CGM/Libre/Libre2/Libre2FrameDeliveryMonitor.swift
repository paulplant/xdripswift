//
//  Libre2FrameDeliveryMonitor.swift
//  xdrip
//
//  Created by Paul Plant on 31/8/26.
//  Copyright © 2026 Johan Degraeve. All rights reserved.
//

import Foundation

/// Reassembles the three CoreBluetooth notifications that normally make up one Libre 2 frame.
///
/// A completed buffer is cleared immediately. This matters when CoreBluetooth releases several
/// historical frames in one burst: waiting for the normal three-second inter-frame gap would make
/// the second frame append to the completed first frame and prevent either frame being classified.
struct Libre2FrameAssembler {
    enum Result: Equatable {
        case incomplete
        case complete(frame: Data, assemblyDuration: TimeInterval)
        case oversized(receivedByteCount: Int)
    }

    struct TimedOutPartialFrame: Equatable {
        let discardedByteCount: Int
        let assemblyDuration: TimeInterval
    }

    /// Reports frame assembly and any timeout that occurred while accepting the new fragment.
    /// Keeping both results means the fragment that reveals a timeout can immediately become the
    /// first fragment of the next frame instead of being thrown away for diagnostic convenience.
    struct AppendResult: Equatable {
        let frameResult: Result
        let timedOutPartialFrame: TimedOutPartialFrame?
    }

    private let expectedByteCount: Int
    private let assemblyTimeout: Duration

    private var buffer = Data()
    private var firstFragmentArrival: ContinuousClock.Instant?

    init(expectedByteCount: Int = 46, assemblyTimeout: Duration = .seconds(3)) {
        self.expectedByteCount = expectedByteCount
        self.assemblyTimeout = assemblyTimeout
    }

    mutating func append(_ fragment: Data, arrival: ContinuousClock.Instant) -> AppendResult {
        var timedOutPartialFrame: TimedOutPartialFrame?

        if let firstFragmentArrival,
           firstFragmentArrival.duration(to: arrival) > assemblyTimeout
        {
            timedOutPartialFrame = TimedOutPartialFrame(
                discardedByteCount: buffer.count,
                assemblyDuration: firstFragmentArrival.duration(to: arrival).timeInterval
            )
            reset()
        }

        if firstFragmentArrival == nil {
            firstFragmentArrival = arrival
        }

        buffer.append(fragment)

        guard buffer.count >= expectedByteCount else {
            return AppendResult(frameResult: .incomplete, timedOutPartialFrame: timedOutPartialFrame)
        }

        guard buffer.count == expectedByteCount else {
            let receivedByteCount = buffer.count
            reset()
            return AppendResult(
                frameResult: .oversized(receivedByteCount: receivedByteCount),
                timedOutPartialFrame: timedOutPartialFrame
            )
        }

        let completedFrame = buffer
        let assemblyDuration = firstFragmentArrival?.duration(to: arrival).timeInterval ?? 0
        reset()

        return AppendResult(
            frameResult: .complete(frame: completedFrame, assemblyDuration: assemblyDuration),
            timedOutPartialFrame: timedOutPartialFrame
        )
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        firstFragmentArrival = nil
    }
}

/// Compares Libre's internal sensor-minute counter with the monotonic arrival chronology.
///
/// The baseline deliberately does not move forward with every accepted frame. A rolling baseline
/// would hide the observed failure mode, where each sensor minute took two or three real minutes to
/// arrive: every individual interval would look only slightly late while the total delay continued
/// to grow. Keeping one baseline makes that accumulated delay visible.
struct Libre2FrameDeliveryMonitor {
    enum Disposition: String, Equatable {
        case current
        case stale
        case counterRegression
    }

    struct Evaluation: Equatable {
        let disposition: Disposition
        let sensorTimeInMinutes: UInt16
        let previousSensorTimeInMinutes: UInt16?
        let sensorAdvanceSincePrevious: Int?
        let interArrivalTime: TimeInterval?
        let sensorAdvanceSinceBaseline: Int
        let elapsedSinceBaseline: TimeInterval
        let estimatedDeliveryLag: TimeInterval?
        let shouldReconnect: Bool
        let recoveredFromStaleDelivery: Bool
        let startedNewSensorTimeline: Bool
        let arrival: ContinuousClock.Instant

        var shouldAccept: Bool {
            disposition == .current
        }

        /// Re-evaluates the same sensor frame at the point where it is about to leave the
        /// transmitter. iOS can suspend the app after CoreBluetooth has delivered a frame but
        /// before parsing or main-queue delivery resumes. Adding that execution delay closes the
        /// gap in which an initially current frame could become stale while waiting in the app.
        func deliveryStatus(at delivery: ContinuousClock.Instant) -> DeliveryStatus {
            let processingDelay = arrival.duration(to: delivery).timeInterval
            let deliveryLag = estimatedDeliveryLag.map { $0 + processingDelay }

            return DeliveryStatus(
                processingDelay: processingDelay,
                estimatedDeliveryLag: deliveryLag,
                shouldAccept: disposition == .current
                    && (deliveryLag ?? .greatestFiniteMagnitude) < Libre2FrameDeliveryMonitor.staleDeliveryThreshold.timeInterval
            )
        }

        /// Anchors the newest generated reading to the frame chronology captured at arrival.
        /// Never allow a negative relative lag to create a future reading timestamp.
        func newestReadingDate(frameArrivalDate: Date) -> Date {
            frameArrivalDate.addingTimeInterval(-max(estimatedDeliveryLag ?? 0, 0))
        }
    }

    struct DeliveryStatus: Equatable {
        let processingDelay: TimeInterval
        let estimatedDeliveryLag: TimeInterval?
        let shouldAccept: Bool
    }

    /// Five minutes is deliberately conservative. It is large enough to tolerate normal radio and
    /// background scheduling jitter, but prevents a frame older than one normal CGM loop interval
    /// from being presented or exported as a current reading.
    static let staleDeliveryThreshold: Duration = .seconds(5 * 60)

    private struct Observation {
        let sensorTimeInMinutes: UInt16
        let arrival: ContinuousClock.Instant
    }

    private var sensorIdentifier: Data?
    private var baseline: Observation?
    private var previousObservation: Observation?
    private var latestAcceptedSensorTimeInMinutes: UInt16?

    /// Once recovery has been requested, continuing stale frames are still rejected but cannot
    /// repeatedly disconnect the sensor. A current frame is required to clear this latch.
    private var reconnectRequestedForCurrentIncident = false

    mutating func evaluate(
        sensorIdentifier: Data,
        sensorTimeInMinutes: UInt16,
        arrival: ContinuousClock.Instant
    ) -> Evaluation {
        let startedNewSensorTimeline = self.sensorIdentifier != sensorIdentifier
        if startedNewSensorTimeline {
            reset(for: sensorIdentifier)
        }

        let observation = Observation(sensorTimeInMinutes: sensorTimeInMinutes, arrival: arrival)

        guard let baseline else {
            self.baseline = observation
            previousObservation = observation
            latestAcceptedSensorTimeInMinutes = sensorTimeInMinutes

            return Evaluation(
                disposition: .current,
                sensorTimeInMinutes: sensorTimeInMinutes,
                previousSensorTimeInMinutes: nil,
                sensorAdvanceSincePrevious: nil,
                interArrivalTime: nil,
                sensorAdvanceSinceBaseline: 0,
                elapsedSinceBaseline: 0,
                estimatedDeliveryLag: 0,
                shouldReconnect: false,
                recoveredFromStaleDelivery: false,
                startedNewSensorTimeline: startedNewSensorTimeline,
                arrival: arrival
            )
        }

        let previousSensorTime = previousObservation?.sensorTimeInMinutes
        let sensorAdvanceSincePrevious = previousSensorTime.map { Int(sensorTimeInMinutes) - Int($0) }
        let interArrivalTime = previousObservation.map { $0.arrival.duration(to: arrival).timeInterval }
        let sensorAdvanceSinceBaseline = Int(sensorTimeInMinutes) - Int(baseline.sensorTimeInMinutes)
        let elapsedSinceBaseline = baseline.arrival.duration(to: arrival).timeInterval

        previousObservation = observation

        // Compare with the last accepted frame, not merely the preceding arrival. Rejected burst
        // frames must not move this boundary and accidentally make an older counter look valid.
        guard latestAcceptedSensorTimeInMinutes.map({ sensorTimeInMinutes >= $0 }) ?? true else {
            let shouldReconnect = requestReconnectIfNeeded()

            return Evaluation(
                disposition: .counterRegression,
                sensorTimeInMinutes: sensorTimeInMinutes,
                previousSensorTimeInMinutes: previousSensorTime,
                sensorAdvanceSincePrevious: sensorAdvanceSincePrevious,
                interArrivalTime: interArrivalTime,
                sensorAdvanceSinceBaseline: sensorAdvanceSinceBaseline,
                elapsedSinceBaseline: elapsedSinceBaseline,
                estimatedDeliveryLag: nil,
                shouldReconnect: shouldReconnect,
                recoveredFromStaleDelivery: false,
                startedNewSensorTimeline: false,
                arrival: arrival
            )
        }

        let expectedElapsedTime = TimeInterval(sensorAdvanceSinceBaseline * 60)
        let estimatedDeliveryLag = elapsedSinceBaseline - expectedElapsedTime

        if estimatedDeliveryLag >= Self.staleDeliveryThreshold.timeInterval {
            let shouldReconnect = requestReconnectIfNeeded()

            return Evaluation(
                disposition: .stale,
                sensorTimeInMinutes: sensorTimeInMinutes,
                previousSensorTimeInMinutes: previousSensorTime,
                sensorAdvanceSincePrevious: sensorAdvanceSincePrevious,
                interArrivalTime: interArrivalTime,
                sensorAdvanceSinceBaseline: sensorAdvanceSinceBaseline,
                elapsedSinceBaseline: elapsedSinceBaseline,
                estimatedDeliveryLag: estimatedDeliveryLag,
                shouldReconnect: shouldReconnect,
                recoveredFromStaleDelivery: false,
                startedNewSensorTimeline: false,
                arrival: arrival
            )
        }

        let recoveredFromStaleDelivery = reconnectRequestedForCurrentIncident
        reconnectRequestedForCurrentIncident = false
        latestAcceptedSensorTimeInMinutes = sensorTimeInMinutes

        return Evaluation(
            disposition: .current,
            sensorTimeInMinutes: sensorTimeInMinutes,
            previousSensorTimeInMinutes: previousSensorTime,
            sensorAdvanceSincePrevious: sensorAdvanceSincePrevious,
            interArrivalTime: interArrivalTime,
            sensorAdvanceSinceBaseline: sensorAdvanceSinceBaseline,
            elapsedSinceBaseline: elapsedSinceBaseline,
            estimatedDeliveryLag: estimatedDeliveryLag,
            shouldReconnect: false,
            recoveredFromStaleDelivery: recoveredFromStaleDelivery,
            startedNewSensorTimeline: false,
            arrival: arrival
        )
    }

    mutating func reset() {
        sensorIdentifier = nil
        baseline = nil
        previousObservation = nil
        latestAcceptedSensorTimeInMinutes = nil
        reconnectRequestedForCurrentIncident = false
    }

    private mutating func reset(for sensorIdentifier: Data) {
        reset()
        self.sensorIdentifier = sensorIdentifier
    }

    private mutating func requestReconnectIfNeeded() -> Bool {
        guard !reconnectRequestedForCurrentIncident else {
            return false
        }

        reconnectRequestedForCurrentIncident = true
        return true
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
