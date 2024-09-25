//
//  XDripWidgetLiveActivity.swift
//  XDripWidget
//
//  Created by Paul Plant on 29/12/23.
//  Copyright © 2023 Johan Degraeve. All rights reserved.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct XDripWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        // Configuration for the activity widget
        ActivityConfiguration(for: XDripWidgetAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 15) {
                        Text("\(context.state.bgValueStringInUserChosenUnit)\(context.state.trendArrow())")
                            .font(.system(size: 90))
                            .bold()
                            .foregroundStyle(context.state.bgTextColor())
                        
                        Text("Last reading at \(context.state.bgReadingDate?.formatted(date: .omitted, time: .shortened) ?? "--:--")")
                            .font(.system(size: 24))
                            .foregroundStyle(.colorTertiary)
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } compactLeading: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.state.bgValueStringInUserChosenUnit)\(context.state.trendArrow())")
                        .font(.system(size: 250))
                        .bold()
                        .foregroundStyle(context.state.bgTextColor())
                        .minimumScaleFactor(0.1)
                }
            } compactTrailing: {
                VStack(alignment: .trailing, spacing: 2) {

                    Text(context.state.deltaChangeStringInUserChosenUnit())
                        .font(.system(size: 180))
                        .fontWeight(.semibold)
                        .foregroundStyle(context.state.deltaChangeTextColor())
                        .minimumScaleFactor(0.1)
                    
                    Text(context.state.bgReadingDate?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                        .foregroundStyle(.gray)
                        .opacity(1)
                        .lineLimit(1)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } minimal: {
                VStack(spacing: 2) {
                    Text("\(context.state.bgValueStringInUserChosenUnit)")
                        .font(.system(size: 24))
                        .bold()
                        .foregroundStyle(context.state.bgTextColor())
                        .minimumScaleFactor(0.1)
                }
            }
            .widgetURL(URL(string: "xdripswift"))
            .keylineTint(context.state.bgTextColor())
        }
        .extraFamilies()  // Method to add supplemental families
    }
}

struct XDripWidgetLiveActivity_Previews: PreviewProvider {
   
    static func bgDateArray() -> [Date] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-3600 * 12)
        var currentDate = startDate
        var dateArray: [Date] = []

        while currentDate < endDate {
            dateArray.append(currentDate)
            currentDate = currentDate.addingTimeInterval(60 * 5)
        }
        return dateArray
    }

    static func bgValueArray() -> [Double] {
        var bgValueArray: [Double] = Array(repeating: 0, count: 144)
        var currentValue: Double = 100
        var increaseValues = true

        for index in bgValueArray.indices {
            let randomValue = Double(Int.random(in: -10..<10))
            
            if currentValue < 80 {
                increaseValues = true
                bgValueArray[index] = currentValue + abs(randomValue)
            } else if currentValue > 160 {
                increaseValues = false
                bgValueArray[index] = currentValue - abs(randomValue)
            } else {
                bgValueArray[index] = currentValue + (increaseValues ? randomValue : -randomValue)
            }
            currentValue = bgValueArray[index]
        }
        return bgValueArray
    }

    static let attributes = XDripWidgetAttributes()

    static let contentState = XDripWidgetAttributes.ContentState(
        bgReadingValues: bgValueArray(),
        bgReadingDates: bgDateArray(),
        isMgDl: true,
        slopeOrdinal: 5,
        deltaChangeInMgDl: -2,
        urgentLowLimitInMgDl: 70,
        lowLimitInMgDl: 80,
        highLimitInMgDl: 140,
        urgentHighLimitInMgDl: 180,
        liveActivitySize: .large,
        dataSourceDescription: "Dexcom G6"
    )

    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Notification")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Compact")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Expanded")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Minimal")
    }
}

struct LockScreenLiveActivityContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @State var context: ActivityViewContext<XDripWidgetAttributes>

    var body: some View {
        VStack {
            Group {
                if context.state.liveActivitySize == .minimal {
                    HStack(alignment: .center) {
                        // Display glucose value and trend arrow
                        Text("\(context.state.bgValueStringInUserChosenUnit) \(context.state.trendArrow())")
                            .font(.system(size: 35))
                            .bold()
                            .foregroundStyle(context.state.bgTextColor())
                            .minimumScaleFactor(0.1)
                            .lineLimit(1)
                        
                        Text(context.state.bgReadingDate?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                            .foregroundStyle(.gray)
                            .opacity(1)
                            .lineLimit(1)
                            .font(.system(size: 18))
                        
                        Spacer()
 
                        if context.state.warnUserToOpenApp {
                            Text("Open app...")
                                .font(.footnote)
                                .bold()
                                .foregroundStyle(.black)
                                .multilineTextAlignment(.center)
                                .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                .background(.cyan)
                                .opacity(0.9)
                                .cornerRadius(10)
                            
                            Spacer()
                        }
                 
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(context.state.deltaChangeStringInUserChosenUnit())
                                .font(.title)
                                .fontWeight(.semibold)
                                .foregroundStyle(context.state.deltaChangeTextColor())
                                .minimumScaleFactor(0.2)
                                .lineLimit(1)
                            
                            Text(context.state.bgUnitString)
                                .font(.title)
                                .foregroundStyle(.colorTertiary)
                                .minimumScaleFactor(0.2)
                                .lineLimit(1)
                        }
                    }
                    .activityBackgroundTint(.black) // Black background for live activity
                    .padding([.top, .bottom], 0)
                    .padding([.leading, .trailing], 20)

                } else if context.state.liveActivitySize == .normal {
                    HStack(spacing: 30) {
                        VStack(spacing: 0) {
          
                            Text("\(context.state.bgValueStringInUserChosenUnit)\(context.state.trendArrow())")
                                .font(.system(size: 44))
                                .bold()
                                .foregroundStyle(context.state.bgTextColor())
                                .minimumScaleFactor(0.1)
                                .lineLimit(1)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
             
                                Text(context.state.deltaChangeStringInUserChosenUnit())
                                    .font(.system(size: 20))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(context.state.deltaChangeTextColor())
                                    .minimumScaleFactor(0.2)
                                    .lineLimit(1)
                                
                                Text(context.state.bgUnitString)
                                    .font(.system(size: 20))
                                    .foregroundStyle(.colorTertiary)
                                    .minimumScaleFactor(0.2)
                                    .lineLimit(1)
                                
                      
                                Text(context.state.bgReadingDate?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                                    .foregroundStyle(.gray)
                                    .opacity(1)
                                    .lineLimit(1)
                                    .font(.system(size: 24))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
            
                        ZStack {
                            GlucoseChartView(
                                glucoseChartType: .liveActivity,
                                bgReadingValues: context.state.bgReadingValues,
                                bgReadingDates: context.state.bgReadingDates,
                                isMgDl: context.state.isMgDl,
                                urgentLowLimitInMgDl: context.state.urgentLowLimitInMgDl,
                                lowLimitInMgDl: context.state.lowLimitInMgDl,
                                highLimitInMgDl: context.state.highLimitInMgDl,
                                urgentHighLimitInMgDl: context.state.urgentHighLimitInMgDl,
                                liveActivitySize: .normal,
                                hoursToShowScalingHours: nil,
                                glucoseCircleDiameterScalingHours: nil,
                                overrideChartHeight: nil,
                                overrideChartWidth: nil,
                                highContrast: nil
                            )
                      
                            if context.state.warnUserToOpenApp {
                                VStack(alignment: .center) {
                                    Spacer()
                                    Text("Open \(ConstantsHomeView.applicationName)")
                                        .font(.footnote)
                                        .bold()
                                        .foregroundStyle(.black)
                                        .multilineTextAlignment(.center)
                                        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                        .background(.cyan)
                                        .opacity(0.9)
                                        .cornerRadius(10)
                                    Spacer()
                                }
                                .padding(8)
                            }
                        }
                    }
                    .activityBackgroundTint(.black)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                } else {
                   
                    ZStack {
                        VStack(spacing: 0) {
                            HStack(alignment: .center) {
                                // Glucose value and trend arrow
                                Text("\(context.state.bgValueStringInUserChosenUnit) \(context.state.trendArrow())")
                                    .font(.system(size: 32))
                                    .fontWeight(.bold)
                                    .foregroundStyle(context.state.bgTextColor())
                                    .scaledToFill()
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                                
                                Spacer()
                            
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(context.state.deltaChangeStringInUserChosenUnit())
                                        .font(.system(size: 28))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(context.state.deltaChangeTextColor())
                                        .lineLimit(1)
                                    Text(context.state.bgUnitString)
                                        .font(.system(size: 28))
                                        .foregroundStyle(.colorTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                            .padding([.leading, .trailing], 15)
                   
                            GlucoseChartView(
                                glucoseChartType: .liveActivity,
                                bgReadingValues: context.state.bgReadingValues,
                                bgReadingDates: context.state.bgReadingDates,
                                isMgDl: context.state.isMgDl,
                                urgentLowLimitInMgDl: context.state.urgentLowLimitInMgDl,
                                lowLimitInMgDl: context.state.lowLimitInMgDl,
                                highLimitInMgDl: context.state.highLimitInMgDl,
                                urgentHighLimitInMgDl: context.state.urgentHighLimitInMgDl,
                                liveActivitySize: .large,
                                hoursToShowScalingHours: nil,
                                glucoseCircleDiameterScalingHours: nil,
                                overrideChartHeight: nil,
                                overrideChartWidth: nil,
                                highContrast: nil
                            )
                       
                            HStack {
                                Text(context.state.dataSourceDescription)
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(.colorSecondary)
                                
                                Spacer()
                                
                                Text("Last reading at \(context.state.bgReadingDate?.formatted(date: .omitted, time: .shortened) ?? "--:--")")
                                    .font(.caption)
                                    .foregroundStyle(.colorTertiary)
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 10)
                            .padding([.leading, .trailing], 15)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(0)
                 
                        if context.state.warnUserToOpenApp {
                            VStack(alignment: .center) {
                                Text("Please open \(ConstantsHomeView.applicationName)")
                                    .font(.footnote)
                                    .bold()
                                    .foregroundStyle(.black)
                                    .multilineTextAlignment(.center)
                                    .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                    .background(.cyan)
                                    .opacity(0.9)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .activityBackgroundTint(.black)
                }
            }
        }
    }
}

struct EarlierLockScreenLiveActivityContentView: View {
    let context: ActivityViewContext<XDripWidgetAttributes>
    
    var body: some View {
        LockScreenLiveActivityContentView(context: context)
    }
}

@available(iOS 18, *)
struct SmartStackLiveActivityContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @State var context: ActivityViewContext<XDripWidgetAttributes>
    
    var body: some View {
        ZStack {
        
            HStack(alignment: .center) {
                HStack(alignment: .center) {
                    Text(context.state.bgValueStringInUserChosenUnit)
                        .font(.system(size: 24))
                        .foregroundStyle(context.state.bgTextColor())
                        .lineLimit(1)
                        .fontWeight(.semibold)
                    
                    Text(context.state.trendArrow())
                        .font(.system(size: 15))
                        .foregroundStyle(context.state.bgTextColor())
                        .lineLimit(1)
                        .fontWeight(.semibold)
                }
                
                Spacer()
      
                if context.state.warnUserToOpenApp {
                    Text("Open app...")
                        .font(.footnote)
                        .bold()
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .background(Color.cyan.opacity(0.8))
                        .cornerRadius(10)
                    
                    Spacer()
                }
                
                VStack(alignment: .center, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        
                        Text(context.state.deltaChangeStringInUserChosenUnit())
                            .font(.system(size: 15))
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(context.state.deltaChangeTextColor())
                            .minimumScaleFactor(0.2)
                            .lineLimit(1)
                        
                        Text(context.state.bgUnitString)
                            .font(.system(size: 15))
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.2)
                            .lineLimit(1)
                    }
              
                    
                    Text(context.state.bgReadingDate?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                        .minimumScaleFactor(0.2)
                        .lineLimit(1)
                }
            }
            .padding([.top, .bottom], 0)
            .padding([.leading, .trailing], 20)
        }
        .activityBackgroundTint(.black)
    }
}

@available(iOS 18.0, *)
struct NewerLockScreenLiveActivityContentView: View {
    @Environment(\.activityFamily) var activityFamily // Detects the size/family of the activity
    @State var context: ActivityViewContext<XDripWidgetAttributes>
    
    var body: some View {
        // Adjust content based on the widget size (small, medium, etc.)
        switch activityFamily {
        case .small:
            SmartStackLiveActivityContentView(context: context)
        case .medium:
            LockScreenLiveActivityContentView(context: context)
        @unknown default:
            LockScreenLiveActivityView(context: context)
        }
    }
}

struct LockScreenLiveActivityView: View {
    @State var context: ActivityViewContext<XDripWidgetAttributes>
    
    var body: some View {
        Group {
            // Use new view for iOS 18 or fallback for older versions
            if #available(iOS 18.0, *) {
                NewerLockScreenLiveActivityContentView(context: context)
            } else {
                LockScreenLiveActivityContentView(context: context)
            }
        }
    }
}
