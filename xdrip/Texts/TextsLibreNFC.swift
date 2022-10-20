import Foundation

class TextsLibreNFC {
    
    static private let filename = "LibreNFC"
    
    static let scanComplete: String = {
        return NSLocalizedString("scanComplete", tableName: filename, bundle: Bundle.main, value: "Sensor succesfully scanned", comment: "after scanning NFC, scan complete message")
    }()

    static let holdTopOfIphoneNearSensor: String = {
        return NSLocalizedString("holdTopOfIphoneNearSensor", tableName: filename, bundle: Bundle.main, value: "Hold the top of your iPhone near the sensor to scan.\r\n\r\nIt is possible that this scan will fail, so be ready to check the screen for any error message and follow the instructions provided to repeat the scan.", comment: "when NFC scanning is started, this message will appear")
    }()
    
    static let deviceMustSupportNFC: String = {
        return NSLocalizedString("deviceMustSupportNFC", tableName: filename, bundle: Bundle.main, value: "This iPhone does not support NFC", comment: "Device must support NFC")
    }()
    
    static let deviceMustSupportIOS14: String = {
        return NSLocalizedString("deviceMustSupportIOS14", tableName: filename, bundle: Bundle.main, value: "To connect to Libre 2, this iPhone needs upgrading to iOS14", comment: "Device must support at least iOS 14.0")
    }()
    
    static let donotusethelibrelinkapp: String = {
        return String(format: NSLocalizedString("donotusethelibrelinkapp", tableName: filename, bundle: Bundle.main, value: "Connected via bluetooth to a Libre 2.\r\n\r\nIf you want to keeping scanning the sensor with the official Libre app, then you must disable bluetooth permission for the Libre app in your iPhone settings. \r\n\r\nOtherwise, scanning the NFC with the Libre app will break the connection between %@ and the Libre 2.", comment: "After Libre NFC scanning, and after successful bluetooth connection, this message will be shown to explain that he or she should not allow bluetooth permission on the Libre app"), ConstantsHomeView.applicationName)
    }()
    
    static let connectedLibre2DoesNotMatchScannedLibre2: String = {
        return String(format: NSLocalizedString("connectedLibre2DoesNotMatchScannedLibre2", tableName: filename, bundle: Bundle.main, value: "You have scanned a new Libre sensor, but %@ has connected via Bluetooth to a different sensor (probably the previous one)\r\n\r\nTo solve this :\r\n- Do NOT delete this old sensor just yet. Click 'Disconnect' or 'Stop Scanning'\r\n- Go back to the previous screen and add a new CGM of type Libre 2 and scan again.\r\n\r\n%@ should now try and connect to the new sensor.\r\n\r\nIf you accidentally deleted the old sensor from the app then before adding the new one, stop the old one from transmitting by placing it in tin foil or in the microwave.", comment: "The user has connected to another (older?) Libre 2 with bluetooth than the one for which NFC scan was done, in that case, inform user that he/she should click 'disconnect', add a new CGM sensor and scan again."), ConstantsHomeView.applicationName, ConstantsHomeView.applicationName)
    }()
    
    static let nfcErrorRetryScan: String = {
        return NSLocalizedString("nfcErrorRetryScan", tableName: filename, bundle: Bundle.main, value: "An error occured while scanning the sensor with your iPhone. Do NOT ignore this error as you will NOT get any readings.\r\n\r\nClick the 'Scan' button or click 'Back' and add the Libre 2 again, and scan again.\r\n\r\nYou need to keep repeating this action until you get a 'Scan Complete' message. This may take many attempts.", comment: "Sometimes NFC scanning creates errors, retrying solves the problem. This is to explain this to the user")
    }()
    
}
