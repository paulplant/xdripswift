//
//  Libre2FrameDeliveryMonitorTests.swift
//  xdripTests
//
//  Created by Paul Plant on 31/8/26.
//  Copyright © 2026 Johan Degraeve. All rights reserved.
//

import XCTest
@testable import xdrip

final class Libre2FrameDeliveryMonitorTests: XCTestCase {
    private let sensorIdentifier = Data([0x01, 0x02, 0x03, 0x04])
    private let otherSensorIdentifier = Data([0x05, 0x06, 0x07, 0x08])

    func testFirstFrameEstablishesCurrentTimeline() {
        var monitor = Libre2FrameDeliveryMonitor()
        let now = ContinuousClock.now

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_000,
            arrival: now
        )

        XCTAssertTrue(evaluation.shouldAccept)
        XCTAssertEqual(evaluation.disposition, .current)
        XCTAssertEqual(evaluation.estimatedDeliveryLag, 0)
        XCTAssertFalse(evaluation.shouldReconnect)
        XCTAssertTrue(evaluation.startedNewSensorTimeline)
    }

    func testNormalSensorProgressRemainsCurrent() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_010,
            arrival: start.advanced(by: .seconds(10 * 60 + 20))
        )

        XCTAssertTrue(evaluation.shouldAccept)
        XCTAssertEqual(evaluation.sensorAdvanceSinceBaseline, 10)
        XCTAssertEqual(evaluation.estimatedDeliveryLag ?? -1, 20, accuracy: 0.001)
    }

    func testFrameThatBecomesStaleDuringSuspensionIsRejectedBeforeDelivery() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            // Mirrors the reported trace: 271 seconds behind at arrival, then 4,773 seconds
            // waiting for the app to resume before the frame reached application delivery.
            arrival: start.advanced(by: .seconds(60 + 271))
        )

        XCTAssertTrue(evaluation.shouldAccept, "The frame is still eligible at CoreBluetooth arrival")

        let deliveryStatus = evaluation.deliveryStatus(
            at: start.advanced(by: .seconds(60 + 271 + 4_773))
        )

        XCTAssertFalse(deliveryStatus.shouldAccept)
        XCTAssertEqual(deliveryStatus.processingDelay, 4_773, accuracy: 0.001)
        XCTAssertEqual(deliveryStatus.estimatedDeliveryLag ?? -1, 5_044, accuracy: 0.001)
    }

    func testFrameDeliveredWithinRemainingFreshnessWindowIsAccepted() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            arrival: start.advanced(by: .seconds(2 * 60))
        )
        let deliveryStatus = evaluation.deliveryStatus(
            at: start.advanced(by: .seconds(3 * 60))
        )

        XCTAssertTrue(deliveryStatus.shouldAccept)
        XCTAssertEqual(deliveryStatus.processingDelay, 60, accuracy: 0.001)
        XCTAssertEqual(deliveryStatus.estimatedDeliveryLag ?? -1, 2 * 60, accuracy: 0.001)
    }

    func testNewestReadingDateIsAnchoredToArrivalChronology() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            arrival: start.advanced(by: .seconds(3 * 60))
        )
        let frameArrivalDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            evaluation.newestReadingDate(frameArrivalDate: frameArrivalDate),
            frameArrivalDate.addingTimeInterval(-2 * 60)
        )
    }

    func testNegativeRelativeLagCannotCreateFutureReadingDate() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            arrival: start.advanced(by: .seconds(20))
        )
        let frameArrivalDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            evaluation.newestReadingDate(frameArrivalDate: frameArrivalDate),
            frameArrivalDate
        )
    }

    func testCumulativeSlowDeliveryEventuallyBecomesStale() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let firstSlowFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            arrival: start.advanced(by: .seconds(3 * 60))
        )
        let secondSlowFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_002,
            arrival: start.advanced(by: .seconds(6 * 60))
        )
        let staleFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_003,
            arrival: start.advanced(by: .seconds(9 * 60))
        )

        XCTAssertTrue(firstSlowFrame.shouldAccept)
        XCTAssertTrue(secondSlowFrame.shouldAccept)
        XCTAssertFalse(staleFrame.shouldAccept)
        XCTAssertEqual(staleFrame.disposition, .stale)
        XCTAssertEqual(staleFrame.estimatedDeliveryLag ?? -1, 6 * 60, accuracy: 0.001)
        XCTAssertTrue(staleFrame.shouldReconnect)
    }

    func testOnlyOneReconnectIsRequestedDuringAStaleIncident() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let firstStaleFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            arrival: start.advanced(by: .seconds(10 * 60))
        )
        let continuingStaleFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_002,
            arrival: start.advanced(by: .seconds(11 * 60))
        )

        XCTAssertTrue(firstStaleFrame.shouldReconnect)
        XCTAssertFalse(continuingStaleFrame.shouldReconnect)
        XCTAssertFalse(continuingStaleFrame.shouldAccept)
    }

    func testHistoricalBurstIsRejectedUntilCounterCatchesUp() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let firstStaleFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            arrival: start.advanced(by: .seconds(10 * 60))
        )
        let stillStaleInBurst = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_005,
            arrival: start.advanced(by: .seconds(10 * 60))
        )
        let caughtUpFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_010,
            arrival: start.advanced(by: .seconds(10 * 60))
        )

        XCTAssertFalse(firstStaleFrame.shouldAccept)
        XCTAssertFalse(stillStaleInBurst.shouldAccept)
        XCTAssertTrue(caughtUpFrame.shouldAccept)
        XCTAssertTrue(caughtUpFrame.recoveredFromStaleDelivery)
        XCTAssertEqual(caughtUpFrame.estimatedDeliveryLag ?? -1, 0, accuracy: 0.001)
    }

    func testCurrentFrameAfterReconnectClearsRecoveryLatch() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)
        _ = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_001,
            arrival: start.advanced(by: .seconds(10 * 60))
        )

        let recoveredFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_010,
            arrival: start.advanced(by: .seconds(10 * 60 + 5))
        )
        let laterStaleFrame = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_011,
            arrival: start.advanced(by: .seconds(20 * 60))
        )

        XCTAssertTrue(recoveredFrame.recoveredFromStaleDelivery)
        XCTAssertTrue(laterStaleFrame.shouldReconnect)
    }

    func testCounterRegressionIsRejectedAndRequestsRecovery() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 999,
            arrival: start.advanced(by: .seconds(60))
        )

        XCTAssertFalse(evaluation.shouldAccept)
        XCTAssertEqual(evaluation.disposition, .counterRegression)
        XCTAssertNil(evaluation.estimatedDeliveryLag)
        XCTAssertTrue(evaluation.shouldReconnect)
    }

    func testCounterRegressionIsComparedWithLastAcceptedFrame() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)
        _ = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_010,
            arrival: start.advanced(by: .seconds(10 * 60))
        )

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_009,
            arrival: start.advanced(by: .seconds(10 * 60 + 1))
        )

        XCTAssertFalse(evaluation.shouldAccept)
        XCTAssertEqual(evaluation.disposition, .counterRegression)
        XCTAssertTrue(evaluation.shouldReconnect)
    }

    func testRejectedFramesDoNotLowerAcceptedCounterBoundary() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 1_000, arrival: start)
        _ = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_010,
            arrival: start.advanced(by: .seconds(10 * 60))
        )
        _ = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_009,
            arrival: start.advanced(by: .seconds(10 * 60 + 1))
        )

        let evaluation = monitor.evaluate(
            sensorIdentifier: sensorIdentifier,
            sensorTimeInMinutes: 1_009,
            arrival: start.advanced(by: .seconds(10 * 60 + 2))
        )

        XCTAssertFalse(evaluation.shouldAccept)
        XCTAssertEqual(evaluation.disposition, .counterRegression)
        XCTAssertFalse(evaluation.shouldReconnect)
    }

    func testDifferentSensorIdentifierStartsFreshTimeline() {
        var monitor = Libre2FrameDeliveryMonitor()
        let start = ContinuousClock.now
        _ = monitor.evaluate(sensorIdentifier: sensorIdentifier, sensorTimeInMinutes: 10_000, arrival: start)

        let evaluation = monitor.evaluate(
            sensorIdentifier: otherSensorIdentifier,
            sensorTimeInMinutes: 5,
            arrival: start.advanced(by: .seconds(60))
        )

        XCTAssertTrue(evaluation.shouldAccept)
        XCTAssertTrue(evaluation.startedNewSensorTimeline)
        XCTAssertEqual(evaluation.sensorAdvanceSinceBaseline, 0)
    }
}

final class Libre2FrameAssemblerTests: XCTestCase {
    func testConsecutiveFramesCompleteWithoutWaitingForTimeout() {
        var assembler = Libre2FrameAssembler(expectedByteCount: 6)
        let start = ContinuousClock.now

        XCTAssertEqual(assembler.append(Data([0, 1]), arrival: start).frameResult, .incomplete)
        XCTAssertEqual(assembler.append(Data([2, 3]), arrival: start).frameResult, .incomplete)
        XCTAssertEqual(
            assembler.append(Data([4, 5]), arrival: start).frameResult,
            .complete(frame: Data([0, 1, 2, 3, 4, 5]), assemblyDuration: 0)
        )

        XCTAssertEqual(assembler.append(Data([6, 7, 8]), arrival: start).frameResult, .incomplete)
        XCTAssertEqual(
            assembler.append(Data([9, 10, 11]), arrival: start).frameResult,
            .complete(frame: Data([6, 7, 8, 9, 10, 11]), assemblyDuration: 0)
        )
    }

    func testPartialFrameIsDiscardedAfterAssemblyTimeout() {
        var assembler = Libre2FrameAssembler(expectedByteCount: 6, assemblyTimeout: .seconds(3))
        let start = ContinuousClock.now

        XCTAssertEqual(assembler.append(Data([0, 1, 2]), arrival: start).frameResult, .incomplete)

        let resultAfterTimeout = assembler.append(
            Data([3, 4, 5]),
            arrival: start.advanced(by: .seconds(4))
        )

        XCTAssertEqual(resultAfterTimeout.frameResult, .incomplete)
        XCTAssertEqual(
            resultAfterTimeout.timedOutPartialFrame,
            Libre2FrameAssembler.TimedOutPartialFrame(discardedByteCount: 3, assemblyDuration: 4)
        )

        // The fragment that exposed the timeout must remain as the start of the next frame.
        XCTAssertEqual(
            assembler.append(Data([6, 7, 8]), arrival: start.advanced(by: .seconds(5))).frameResult,
            .complete(frame: Data([3, 4, 5, 6, 7, 8]), assemblyDuration: 1)
        )
    }

    func testOversizedFrameIsDiscardedAndNextFrameCanComplete() {
        var assembler = Libre2FrameAssembler(expectedByteCount: 6)
        let start = ContinuousClock.now

        XCTAssertEqual(
            assembler.append(Data([0, 1, 2, 3, 4, 5, 6]), arrival: start).frameResult,
            .oversized(receivedByteCount: 7)
        )
        XCTAssertEqual(
            assembler.append(Data([7, 8, 9, 10, 11, 12]), arrival: start).frameResult,
            .complete(frame: Data([7, 8, 9, 10, 11, 12]), assemblyDuration: 0)
        )
    }
}

final class Libre2BLEUtilitiesSensorTimeTests: XCTestCase {
    func testReadsLittleEndianSensorMinuteCounter() throws {
        var frame = Data(repeating: 0, count: 42)
        frame[40] = 0x34
        frame[41] = 0x12

        XCTAssertEqual(
            try Libre2BLEUtilities.sensorTimeInMinutes(fromDecryptedFrame: frame),
            0x1234
        )
    }

    func testRejectsFrameWithoutSensorMinuteCounter() {
        XCTAssertThrowsError(
            try Libre2BLEUtilities.sensorTimeInMinutes(fromDecryptedFrame: Data(repeating: 0, count: 41))
        )
    }
}
