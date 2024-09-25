//
//  SmartStackWatchOS.swift
//  xdrip
//
//  Created by Marian Dugaesescu on 25/09/2024.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import WidgetKit
import SwiftUI


extension WidgetConfiguration
{
    func extraFamilies() -> some WidgetConfiguration
    {
        if #available(iOSApplicationExtension 18.0, *) {
            return self.supplementalActivityFamilies([ActivityFamily.small, ActivityFamily.medium])
            
        } else {
            return self
        }
    }
}
