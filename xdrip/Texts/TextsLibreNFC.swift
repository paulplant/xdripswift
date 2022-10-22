import Foundation

class TextsLibreNFC {
    
    static private let filename = "LibreNFC"
    
    static let scanComplete: String = {
        return NSLocalizedString("scanComplete", tableName: filename, bundle: Bundle.main, value: "Sensor scan complete", comment: "after scanning NFC, scan complete message")
    }()

    static let holdTopOfIphoneNearSensor: String = {
        return NSLocalizedString("holdTopOfIphoneNearSensor", tableName: filename, bundle: Bundle.main, value: "Hold the top of your iPhone near the sensor until it stops vibrating.", comment: "when NFC scanning is started, this message will appear")
    }()
    
    static let deviceMustSupportNFC: String = {
        return NSLocalizedString("deviceMustSupportNFC", tableName: filename, bundle: Bundle.main, value: "This iPhone does not support NFC", comment: "Device must support NFC")
    }()
    
    static let deviceMustSupportIOS14: String = {
        return NSLocalizedString("deviceMustSupportIOS14", tableName: filename, bundle: Bundle.main, value: "To connect to Libre 2, this iPhone needs upgrading to iOS14", comment: "Device must support at least iOS 14.0")
    }()
    
    static let donotusethelibrelinkapp: String = {
        return String(format: NSLocalizedString("donotusethelibrelinkapp", tableName: filename, bundle: Bundle.main, value: "Connected to Libre 2.\n\nPlease ensure you have disabled bluetooth permission for the Libre app in your iPhone settings.\n\nIf you don't do this, when you scan with the Libre app you will break the connection between %@ and the Libre 2.", comment: "After Libre NFC scanning, and after successful bluetooth connection, this message will be shown to explain that he or she should not allow bluetooth permission on the Libre app"), ConstantsHomeView.applicationName)
    }()
    
    static let connectedLibre2DoesNotMatchScannedLibre2: String = {
        return String(format: NSLocalizedString("connectedLibre2DoesNotMatchScannedLibre2", tableName: filename, bundle: Bundle.main, value: "You have scanned a new Libre sensor, but %@ has connected to a different sensor (probably the previous one).\n\nTo solve this do NOT delete this old sensor just yet. Click 'Disconnect' or 'Stop Scanning', go back to the previous screen and add a new CGM of type Libre 2 and scan the sensor again.\n\n%@ should now try and connect to the new sensor.\n\nIf you already deleted the old sensor from the app then before trying to add the new one again, stop the old one from transmitting by placing it in tin foil or in the microwave.", comment: "The user has connected to another (older?) Libre 2 with bluetooth than the one for which NFC scan was done, in that case, inform user that he/she should click 'disconnect', add a new CGM sensor and scan again."), ConstantsHomeView.applicationName, ConstantsHomeView.applicationName)
    }()
    
    static let nfcErrorRetryScan: String = {
        return NSLocalizedString("nfcErrorRetryScan", tableName: filename, bundle: Bundle.main, value: "NFC scan error.\n\nTry scanning again.", comment: "Sometimes NFC scanning creates errors, retrying solves the problem. This is to explain this to the user")
    }()
    
}
