//
//  XDripWidgetAttributes.swift
//  xDripWidgetExtension
//
//  Created by Paul Plant on 30/12/23.
//  Copyright © 2023 Johan Degraeve. All rights reserved.
//

import Foundation
import ActivityKit
import WidgetKit
import SwiftUI

struct XDripWidgetAttributes: ActivityAttributes {
    
    public struct ContentState: Codable, Hashable {
        
        // Store values with a 16 bit precision to save payload bytes
        private var bgReadingFloats: [Float16]
        // Expose those conveniently as Doubles
        var bgReadingValues: [Double] {
            bgReadingFloats.map(Double.init)
        }
        
        // To save those precious payload bytes, store only the earliest date as Date
        private var firstDate: Date
        // ...and all other as seconds from that moment.
        // No need for floating points, a second is precise enough for the graph
        // UInt16 maximum value is 65535 so that means 18.2 hours.
        // This would need to be changed if wishing to present a 24 hour chart.
        private var secondsSinceFirstDate: [UInt16]
        // Expose the dates conveniently
        var bgReadingDates: [Date] {
            secondsSinceFirstDate.map { Date(timeInterval: Double($0), since: firstDate) }
        }
        
        // For some reason, ActivityAttributes can't see the main target Assets folder
        // so we'll just duplicate the colors here for now
        // We have to store just the float value instead of the whole Color object to
        // keep the struct conforming to Codable
        private var colorPrimaryWhiteValue: Double = 0.9
        private var colorSecondaryWhiteValue: Double = 0.65
        private var colorTertiaryWhiteValue: Double = 0.45
        
        var isMgDl: Bool
        var slopeOrdinal: Int
        var deltaChangeInMgDl: Double?
        var urgentLowLimitInMgDl: Double
        var lowLimitInMgDl: Double
        var highLimitInMgDl: Double
        var urgentHighLimitInMgDl: Double
        var eventStartDate: Date = Date()
        var warnUserToOpenApp: Bool = true
        var liveActivitySize: LiveActivitySize
        var dataSourceDescription: String
        
        var bgUnitString: String {
            isMgDl ? Texts_Common.mgdl : Texts_Common.mmol
        }
        /// the latest bg reading
        var bgValueInMgDl: Double? {
            bgReadingValues[0]
        }
        /// the latest bg reading date
        var bgReadingDate: Date? {
            bgReadingDates[0]
        }
        
        var bgValueStringInUserChosenUnit: String {
            if let bgReadingDate = bgReadingDate, bgReadingDate > Date().addingTimeInterval(-ConstantsWidgetExtension.bgReadingDateVeryStaleInMinutes) {
                bgReadingValues[0].mgdlToMmolAndToString(mgdl: isMgDl)
            } else {
                isMgDl ? "---" : "-.-"
            }
        }
        
        init(bgReadingValues: [Double], bgReadingDates: [Date], isMgDl: Bool, slopeOrdinal: Int, deltaChangeInMgDl: Double?, urgentLowLimitInMgDl: Double, lowLimitInMgDl: Double, highLimitInMgDl: Double, urgentHighLimitInMgDl: Double, liveActivitySize: LiveActivitySize, dataSourceDescription: String? = "") {
            
            self.bgReadingFloats = bgReadingValues.map(Float16.init)
            
            let firstDate = bgReadingDates.last ?? .now
            self.firstDate = firstDate
            self.secondsSinceFirstDate = bgReadingDates.map { UInt16(truncatingIfNeeded: Int($0.timeIntervalSince(firstDate))) }
            
            self.isMgDl = isMgDl
            self.slopeOrdinal = slopeOrdinal
            self.deltaChangeInMgDl = deltaChangeInMgDl
            self.urgentLowLimitInMgDl = urgentLowLimitInMgDl
            self.lowLimitInMgDl = lowLimitInMgDl
            self.highLimitInMgDl = highLimitInMgDl
            self.urgentHighLimitInMgDl = urgentHighLimitInMgDl
            self.liveActivitySize = liveActivitySize
            self.dataSourceDescription = dataSourceDescription ?? ""
        }
        
        /// Blood glucose color dependant on the user defined limit values and based upon the time since the last reading
        /// - Returns: a Color object either red, yellow or green
        func bgTextColor() -> Color {
            if let bgReadingDate = bgReadingDate, let bgValueInMgDl = bgValueInMgDl {
                if bgReadingDate > Date().addingTimeInterval(-ConstantsWidgetExtension.bgReadingDateStaleInMinutes) {
                    if bgValueInMgDl >= urgentHighLimitInMgDl || bgValueInMgDl <= urgentLowLimitInMgDl {
                        return .red
                    } else if bgValueInMgDl >= highLimitInMgDl || bgValueInMgDl <= lowLimitInMgDl {
                        return .yellow
                    } else {
                        return .green
                    }
                } else {
                    return Color(white: colorTertiaryWhiteValue)
                }
            } else {
                return Color(white: colorTertiaryWhiteValue)
            }
        }
        
        public func backgroundWidgetColor() -> LinearGradient {
            if let bgReadingDate = bgReadingDate, let bgValueInMgDl = bgValueInMgDl {
                if bgReadingDate > Date().addingTimeInterval(-ConstantsWidgetExtension.bgReadingDateStaleInMinutes * 60) {
                    
                    if bgValueInMgDl >= urgentHighLimitInMgDl || bgValueInMgDl <= urgentLowLimitInMgDl {
                        return LinearGradient(
                            gradient: Gradient(colors: [Color.red.opacity(0.7), Color.red.opacity(0.5)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    
                    } else if bgValueInMgDl >= highLimitInMgDl || bgValueInMgDl <= lowLimitInMgDl {
                        return LinearGradient(
                            gradient: Gradient(colors: [Color.yellow.opacity(0.7), Color.yellow.opacity(0.5)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    
                    } else {
                        return LinearGradient(
                            gradient: Gradient(colors: [Color.paleGreen.opacity(0.7), Color.paleGreen.opacity(0.5)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            }
           
            return LinearGradient(
                gradient: Gradient(colors: [Color.paleTurquoise.opacity(0.7), Color.paleTurquoise.opacity(0.5)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
            
            
            
            /// Delta text color dependant on the time since the last reading
            /// - Returns: a Color either white(ish) or gray
            func deltaChangeTextColor() -> Color {
                if let bgReadingDate = bgReadingDate, bgReadingDate > Date().addingTimeInterval(-ConstantsWidgetExtension.bgReadingDateStaleInMinutes) {
                    return Color(white: colorPrimaryWhiteValue)
                } else {
                    return Color(white: colorTertiaryWhiteValue)
                }
            }
            
            
            
            /// convert the optional delta change int (in mg/dL) to a formatted change value in the user chosen unit making sure all zero values are shown as a positive change to follow Nightscout convention
            /// - Returns: a string holding the formatted delta change value (i.e. +0.4 or -6)
            func deltaChangeStringInUserChosenUnit() -> String {
                if let deltaChangeInMgDl = deltaChangeInMgDl, let bgReadingDate = bgReadingDate, bgReadingDate > Date().addingTimeInterval(-ConstantsWidgetExtension.bgReadingDateVeryStaleInMinutes) {
                    let deltaSign: String = deltaChangeInMgDl > 0 ? "+" : ""
                    let valueAsString = deltaChangeInMgDl.mgdlToMmolAndToString(mgdl: isMgDl)
                    
                    // quickly check "value" and prevent "-0mg/dl" or "-0.0mmol/l" being displayed
                    // show unitized zero deltas as +0 or +0.0 as per Nightscout format
                    if (isMgDl) {
                        return (deltaChangeInMgDl > -1 && deltaChangeInMgDl < 1) ?  "+0" : (deltaSign + valueAsString)
                    } else {
                        return (deltaChangeInMgDl > -0.1 && deltaChangeInMgDl < 0.1) ? "+0.0" : (deltaSign + valueAsString)
                    }
                } else {
                    return isMgDl ? "-" : "-.-"
                }
            }
            
            ///  returns a string holding the trend arrow
            /// - Returns: trend arrow string (i.e.  "↑")
            func trendArrow() -> String {
                if let bgReadingDate = bgReadingDate, bgReadingDate > Date().addingTimeInterval(-ConstantsWidgetExtension.bgReadingDateVeryStaleInMinutes) {
                    switch slopeOrdinal {
                    case 7:
                        return "\u{2193}\u{2193}" // ↓↓
                    case 6:
                        return "\u{2193}" // ↓
                    case 5:
                        return "\u{2198}" // ↘
                    case 4:
                        return "\u{2192}" // →
                    case 3:
                        return "\u{2197}" // ↗
                    case 2:
                        return "\u{2191}" // ↑
                    case 1:
                        return "\u{2191}\u{2191}" // ↑↑
                    default:
                        return ""
                    }
                } else {
                    return ""
                }
            }
        }
    }
    

extension Color {
    static let skyBlue = Color(red: 135/255, green: 206/255, blue: 235/255)
    static let paleRed = Color(red: 255/255, green: 182/255, blue: 193/255)
    static let softOrange = Color(red: 255/255, green: 165/255, blue: 0/255)
    static let paleBlue = Color(red: 173/255, green: 216/255, blue: 230/255)
    static let brightWhite = Color(red: 255/255, green: 255/255, blue: 255/255, opacity: 1.0)
    static let paleTurquoise = Color(red: 64/255, green: 224/255, blue: 208/255)
    static let softMagentaRed = Color(red: 255/255, green: 102/255, blue: 178/255)
    static let rubyRed = Color(red: 155/255, green: 17/255, blue: 30/255)
    static let magentaRed = Color(red: 255/255, green: 62/255, blue: 106/255)
    static let appleBlue = Color(red: 14.0/255.0, green: 122.0/255.0, blue: 254.0/255.0)
    static let paleYellow = Color(red: 255/255, green: 255/255, blue: 153/255)
    static let paleGreen = Color(red: 12/255, green: 224/255, blue: 108/255)
}
