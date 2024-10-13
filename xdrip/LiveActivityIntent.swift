//
//  LiveActivityIntent.swift
//  xdrip
//
//  Created by Marian Dugaesescu on 13/10/2024.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

#if canImport(AppIntents)
import AppIntents
#endif
import Foundation


struct RestartLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource {
        "Restart Live Activity"
    }

    static var description: IntentDescription? {
        IntentDescription("Restarts the glucose monitoring live activity.", categoryName: "Live Activity")
    }
   
    @MainActor
    func perform() async throws -> some IntentResult {
        // Fetch the latest glucose data
        let coreDataManager = await CoreDataManager.create(for: ConstantsCoreData.modelName)
        let bgReadingsAccessor = BgReadingsAccessor(coreDataManager: coreDataManager)
        var bgReadings = bgReadingsAccessor.getLatestBgReadings(
            limit: nil,
            fromDate: Date(timeIntervalSinceNow: -14400),
            forSensor: nil,
            ignoreRawData: true,
            ignoreCalculatedValue: false
        )
        
        // Ensure readings are sorted in descending order (most recent first)
        bgReadings.sort { $0.timeStamp > $1.timeStamp }

        guard bgReadings.count >= 2 else {
            throw IntentError.message("Not enough glucose data to calculate trend.")
        }

        var bgReadingValues: [Double] = []
        var bgReadingDates: [Date] = []

        for bgReading in bgReadings {
            bgReadingValues.append(bgReading.calculatedValue)
            bgReadingDates.append(bgReading.timeStamp)
        }

        // Retrieve user settings
        let isMgDl = UserDefaults.standard.bloodGlucoseUnitIsMgDl
        let urgentLowLimitInMgDl = UserDefaults.standard.urgentLowMarkValue
        let lowLimitInMgDl = UserDefaults.standard.lowMarkValue
        let highLimitInMgDl = UserDefaults.standard.highMarkValue
        let urgentHighLimitInMgDl = UserDefaults.standard.urgentHighMarkValue
        let dataSourceDescription = "" // Provide a description if available

        // Get the most recent reading and the previous one
        let currentReading = bgReadings[0]
        let previousReading = bgReadings[1]

        // Calculate delta change
        let deltaChangeInMgDl = currentReading.calculatedValue - previousReading.calculatedValue

        // Calculate the time difference in milliseconds
        let timeDifference = currentReading.timeStamp.timeIntervalSince(previousReading.timeStamp) * 1000 // milliseconds

        // Avoid division by zero
        guard timeDifference != 0 else {
            throw IntentError.message("Time difference between readings is zero.")
        }

        // Calculate the slope (change per millisecond)
        let calculatedValueSlope = deltaChangeInMgDl / timeDifference

        // Calculate slope_by_minute
        let slope_by_minute = calculatedValueSlope * 60000

        // Calculate the slopeOrdinal
        let slopeOrdinal: Int
        if !currentReading.hideSlope {
            switch slope_by_minute {
            case ..<(-3.5):
                slopeOrdinal = 7 // Dropping Fast
            case -3.5 ..< -2:
                slopeOrdinal = 6 // Dropping
            case -2 ..< -1:
                slopeOrdinal = 5 // Slowly Dropping
            case -1 ..< 1:
                slopeOrdinal = 4 // Stable
            case 1 ..< 2:
                slopeOrdinal = 3 // Slowly Rising
            case 2 ..< 3.5:
                slopeOrdinal = 2 // Rising
            default:
                slopeOrdinal = 1 // Rising Fast
            }
        } else {
            slopeOrdinal = 0 // When hideSlope is true
        }

        let size = UserDefaults.standard.liveActivitySize

        // Create the content state
        let contentState = XDripWidgetAttributes.ContentState(
            bgReadingValues: bgReadingValues,
            bgReadingDates: bgReadingDates,
            isMgDl: isMgDl,
            slopeOrdinal: slopeOrdinal,
            deltaChangeInMgDl: deltaChangeInMgDl,
            urgentLowLimitInMgDl: urgentLowLimitInMgDl,
            lowLimitInMgDl: lowLimitInMgDl,
            highLimitInMgDl: highLimitInMgDl,
            urgentHighLimitInMgDl: urgentHighLimitInMgDl,
            liveActivitySize: size,
            dataSourceDescription: dataSourceDescription
        )

        // Restart the live activity
        LiveActivityManager.shared.runActivity(contentState: contentState, forceRestart: true)

        return .result()
    }
}
