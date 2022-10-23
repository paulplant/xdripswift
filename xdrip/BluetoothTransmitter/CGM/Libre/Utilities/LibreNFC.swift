import Foundation
import OSLog
import AVFoundation

#if canImport(CoreNFC)
import CoreNFC

// source : https://github.com/gui-dos/DiaBLE/tree/master/DiaBLE

fileprivate struct NFCCommand {
    let code: UInt8
    let parameters: Data
}

// source : https://github.com/gui-dos/DiaBLE/tree/master/DiaBLE class Sensor
 fileprivate     enum Subcommand: UInt8, CustomStringConvertible {
    case activate        = 0x1b
    case enableStreaming = 0x1e
    case unknown0x1a     = 0x1a
    case unknown0x1c     = 0x1c
    case unknown0x1d     = 0x1d
    case unknown0x1f     = 0x1f
    
    var description: String {
        switch self {
        case .activate:        return "activate"
        case .enableStreaming: return "enable BLE streaming"
        default:               return "[unknown: 0x\(String(format: "%x", rawValue))]"
        }
    }
}

@available(iOS 14.0, *)
class LibreNFC: NSObject, NFCTagReaderSessionDelegate {
    
    // MARK: - properties
    
    /// for trace
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryLibreNFC)
    
    /// will be used to pass back info like sensorUid , patchInfo to delegate
    private(set) weak var libreNFCDelegate: LibreNFCDelegate?
    
    /// fixed unlock code to use
    private let unlockCode: UInt32 = 42
    
    private var failedToScan: Bool = false

    // MARK: - initalizer
    
    init(libreNFCDelegate: LibreNFCDelegate) {
        
        self.libreNFCDelegate = libreNFCDelegate
        
    }
    
    // MARK: - public functions
    
    public func startSession() {
        
        guard NFCTagReaderSession.readingAvailable else {

            xdrip.trace("NFC: NFC is not available@", log: log, category: ConstantsLog.categoryLibreNFC, type: .info)
            
            return

        }
        
        if let tagSession = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main) {

            tagSession.alertMessage = TextsLibreNFC.holdTopOfIphoneNearSensor
            
            tagSession.begin()
            
        }
        
    }

    // MARK: - NFCTagReaderSessionDelegate functions
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        
        xdrip.trace("NFC: tag reader session did become active. Waiting to detect tag/sensor.", log: log, category: ConstantsLog.categoryLibreNFC, type: .info)
        
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        
        if let readerError = error as? NFCReaderError {
            
            if (readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead)
                        && (readerError.code != .readerSessionInvalidationErrorUserCanceled) {
                
                print("NFC Error Code: " + readerError.errorCode.description)
                print("NFC Error Message: " + readerError.localizedDescription)
                
                trace(systemError: error, ownErrorString: "Connection failure:", invalidateSession: true, session: session)
                
            }
            
            if failedToScan { // && !UserDefaults.standard.failedToScan {
                
                xdrip.trace("NFC: scan error. Will try to disconnect the transmitter.", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                
                print("NFC scan failed, trying to trigger the observer")
                
                UserDefaults.standard.failedToScan = true
                
            } else {
                print("NFC scan session closed. Either due to a successful scan or because the user cancelled it.")
                
                // TODO: add a UIAlert to ask if they want to really try connecting without a successful NFC scan
            }
            
        }
        
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        
        // FIXME: messy code whilst initial testing. Clean up and remove all commented out stuff
        //        DispatchQueue.main.async {
        
        xdrip.trace("NFC: did detect tags", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
        
        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }
        
        
        
        //            session.connect(to: firstTag) { error in
        //
        //                if let error = error {
        //
        //                    self.trace(systemError: error, ownErrorString: "Connection failure:", invalidateSession: true, session: session)
        //
        //                    return
        //
        //                }
        
        Task {
            
            let blocks = 43
            let requestBlocks = 3
            
            let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
            let remainder = blocks % requestBlocks
            var dataArray = [Data](repeating: Data(), count: blocks)
            
            var patchInfo = Data()
            var systemInfo: NFCISO15693SystemInfo!
            
            let retries = ConstantsLibre.retryAttemptsForLibre2NFCScans
            var requestedRetry = 0
            //var failedToScan = false

            failedToScan = false
            UserDefaults.standard.failedToScan = false
            UserDefaults.standard.scanSuccessful = false
            
            // get tag response
            repeat {
                failedToScan = false
                if requestedRetry > 0 {
                    //log("NFC: retry # \(requestedRetry)...")
//                    print("NFC: reading tag, attempt # \(requestedRetry)/\(retries)")
                    let debugInfo = "NFC: connecting to tag, retry attempt # \(requestedRetry)/\(retries)"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    session.alertMessage = "Sensor not found\n\nRetrying... # \(requestedRetry)/\(retries)"
                    AudioServicesPlaySystemSound(1519)    // "peek" vibration
                    try await Task.sleep(nanoseconds: 200_000_000)
                } else {
                    xdrip.trace("NFC: connecting to tag", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                }
                do {
                    try await session.connect(to: firstTag)
                    //connectedTag = tag
                } catch {
                    if requestedRetry >= retries {
//
//                        failedToScan = true
                        
                        AudioServicesPlaySystemSound(1107)    // "failed" vibration
                        //log("NFC: stopped retrying to connect after \(requestedRetry) reattempts: \(error.localizedDescription)")
                        let debugInfo = "NFC:       fatal error: stopped trying to connect after \(requestedRetry) attempts: \(error.localizedDescription)"
//                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                        failedToScan = true
                        session.invalidate(errorMessage: "Sensor scan has failed (no sensor found)")
                        return
                    }
                    failedToScan = true
                    requestedRetry += 1
                    //log("NFC: \(error.localizedDescription)")
                    let debugInfo = "NFC:       error: \(error.localizedDescription)"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                }
            } while failedToScan && requestedRetry > 0
            
            
            xdrip.trace("NFC:     - tag response OK, now let's get systemInfo and patchInfo", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
            
            requestedRetry = 0
            
            // get systemInfo
            // get patchInfo
            repeat {
                failedToScan = false
                if requestedRetry > 0 {
                    let debugInfo = "NFC: reading tag info, retry attempt # \(requestedRetry)/\(retries)"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    session.alertMessage = "Sensor found but sensor scan has failed\n\nRetrying...# \(requestedRetry)/\(retries)"
                    AudioServicesPlaySystemSound(1519)    // "peek" vibration
                } else {
                xdrip.trace("NFC: reading tag info", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                }

                // Libre 3 workaround: calling A1 before tag.sytemInfo makes them work
                // The first reading prepends further 7 0xA5 dummy bytes
                
                do {
                    patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                    //print("NFC: patch info (first reading): \(patchInfo.hex) (\(patchInfo.count) bytes), string: \"\(patchInfo.string)\"")
                    if requestedRetry > 0 {
                        let debugInfo = "NFC:     calling A1 before sytemInfo retry attempt # \(requestedRetry)/\(retries)"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    } else {
                        xdrip.trace("NFC:     calling A1 before sytemInfo", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                    }
                } catch {
                    failedToScan = true
                }
                
                do {
                    systemInfo = try await tag.systemInfo(requestFlags: .highDataRate)
                    if requestedRetry > 0 {
                        let debugInfo = "NFC:     getting tag sytemInfo, retry attempt # \(requestedRetry)/\(retries)"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    } else {
                        xdrip.trace("NFC:     getting tag sytemInfo", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                    }
                    AudioServicesPlaySystemSound(1519)    // initial "peek" vibration
                } catch {
                    let debugInfo = "NFC:     - error while getting tag systemInfo: \(error.localizedDescription)"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    if requestedRetry >= retries {
                        
//                        failedToScan = true
                        
                        session.invalidate(errorMessage: "Sensor scan has failed\n\nNo valid information retrieved")
                        AudioServicesPlaySystemSound(1107)    // "failed" vibration
                        let debugInfo = "NFC:     - fatal error: stopped retrying to get tag systemInfo after \(requestedRetry) attempts"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
//                        UserDefaults.standard.failedToScan = true
                        return
                    }
                    failedToScan = true
                    requestedRetry += 1
                }
                
                do {
                    let debugInfo = "NFC:     getting tag patchInfo, retry attempt # \(requestedRetry)/\(retries)"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                } catch {
                    let debugInfo = "NFC:     - error while getting patchInfo: \(error.localizedDescription)"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    if requestedRetry >= retries && systemInfo != nil {
                        requestedRetry = 0 // break repeat
                    } else {
                        if !failedToScan {
                            failedToScan = true
                            requestedRetry += 1
                        }
                    }
                }

            } while failedToScan && requestedRetry > 0
            
            if !failedToScan {
                session.alertMessage = TextsLibreNFC.scanComplete
                xdrip.trace("NFC:     - scan successful. systemInfo and patchInfo retrieved.", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
            } else {
                UserDefaults.standard.failedToScan = true
            }
            
            
            for i in 0 ..< requests {
                
                tag.readMultipleBlocks(requestFlags: [.highDataRate, .address],blockRange: NSRange(UInt8(i * requestBlocks) ... UInt8(i * requestBlocks + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)))) {
                    
                    blockArray, error in
                    
                    if let error = error {
                        
                        let debugInfo = "error while reading multiple blocks (#\(i * requestBlocks) - #\(i * requestBlocks + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0))):"
                        
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                        
                        self.trace(systemError: error, ownErrorString: TextsLibreNFC.nfcErrorRetryScan, invalidateSession: true, session: session)
                        
                        if i != requests - 1 { return }
                        
                    } else {
                        
                        for j in 0 ..< blockArray.count {
                            
                            dataArray[i * requestBlocks + j] = blockArray[j]
                            
                        }
                        
                    }
                    
                    if i == requests - 1 {
                        
                        var fram = Data()
                        
                        var msg = ""
                        
                        for (n, data) in dataArray.enumerated() {
                            if data.count > 0 {
                                fram.append(data)
                                msg += "NFC: block #\(String(format:"%02d", n))  \(data.reduce("", { $0 + String(format: "%02X", $1) + " "}).dropLast())\n"
                            }
                        }
                        
                        if !msg.isEmpty { xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, String(msg.dropLast())) }
                        
                        self.traceICIdentifier(tag: tag)
                        self.traceICManufacturer(tag: tag)
                        self.traceICSerialNumber(tag: tag)
                        self.traceROM(tag: tag)
                        self.traceICReference(systemInfo: systemInfo)
                        self.traceApplicationFamilyIdentifier(systemInfo: systemInfo)
                        self.traceDataStorageFormatIdentifier(systemInfo: systemInfo)
                        self.traceMemorySize(systemInfo: systemInfo)
                        self.traceBlockSize(systemInfo: systemInfo)
                        
                        // get sensorUID and patchInfo and send to delegate
                        let sensorUID = Data(tag.identifier.reversed())
                        //let patchInfo = response
                        
                        // patchInfo should have length 6, which sometimes is not the case, as there are occuring crashes in nfcCommand and Libre2BLEUtilities.streamingUnlockPayload
                        guard patchInfo.count >= 6 else {
                            
                            xdrip.trace("received pachinfo has length < 6", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                            
                            self.trace(systemError: nil, ownErrorString: TextsLibreNFC.nfcErrorRetryScan, invalidateSession: true, session: session)
                            
                            self.failedToScan = true
                            
                            return
                            
                        }
                        
                        self.libreNFCDelegate?.received(sensorUID: sensorUID, patchInfo: patchInfo)
                        
                        self.traceSensorUID(sensorUID: sensorUID)
                        self.tracePatchInfo(patchInfo: patchInfo)
                        
                        // send FRAM to delegate
                        self.libreNFCDelegate?.received(fram: fram)
                        
                        msg = "NFC: dump of "
                        
                        self.readRaw(0xF860, 43 * 8, tag: tag) {
                            
                            let debugInfo = msg + ($2?.localizedDescription ?? $1.hexDump(address: Int($0), header: "FRAM:"))
                            xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                            
                            self.readRaw(0x1A00, 64, tag: tag) {
                                
                                let debugInfo = msg + ($2?.localizedDescription ?? $1.hexDump(address: Int($0), header: "config RAM\n(patchUid at 0x1A08):"))
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                
                                self.readRaw(0xFFAC, 36, tag: tag) {
                                    
                                    var debugInfo = msg + ($2?.localizedDescription ?? $1.hexDump(address: Int($0), header: "patch table for A0-A4 E0-E2 commands:"))
                                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                    
                                    let subCmd: Subcommand = .enableStreaming
                                    
                                    let cmd = self.nfcCommand(subCmd, unlockCode: self.unlockCode, patchInfo: patchInfo, sensorUID: sensorUID)
                                    
                                    debugInfo = "NFC: sending Libre 2 command to " + subCmd.description + " : code: 0x" + String(format: "%0X", cmd.code) + ", parameters: 0x" + cmd.parameters.toHexString() + "unlock code: " +  self.unlockCode.description
                                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                    
                                    tag.customCommand(requestFlags: .highDataRate, customCommandCode: Int(cmd.code), customRequestParameters:  cmd.parameters) { response, error in
                                        
                                        let debugInfo = "NFC: '" + subCmd.description + " command response " + response.count.description + " bytes : 0x" + response.toHexString() + ", error: " +  (error?.localizedDescription ?? "none")
                                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                        
                                        if subCmd == .enableStreaming && response.count == 6 {
                                            
                                            let serialNumber: String = LibreSensorSerialNumber(withUID: sensorUID, with: LibreSensorType.type(patchInfo: patchInfo.toHexString()))?.serialNumber ?? "unknown"
                                            
                                            let debugInfo = "NFC: enabled BLE streaming on Libre 2 " + serialNumber + " unlock code: " + self.unlockCode.description + " MAC address: " + Data(response.reversed()).hexAddress
                                            xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                            
                                            self.libreNFCDelegate?.streamingEnabled(successful : true)
                                            
                                            //self.failedToScan = false
                                            
                                            UserDefaults.standard.scanSuccessful = true
                                            
                                        } else {
                                            // enableStreaming failed ?
                                            self.libreNFCDelegate?.streamingEnabled(successful : false)
                                            
                                            self.failedToScan = true
                                            
                                        }
                                        if subCmd == .activate && response.count == 4 {
                                            
                                            let debugInfo = "NFC: after trying activating received " + response.toHexString() + " for the patch info " + patchInfo.toHexString()
                                            xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                            
                                            // receiving 9d081000 for a patchInfo 9d0830010000 but state remaining .notActivated
                                            // TODO
                                        }
                                        
                                        if !self.failedToScan {
                                            print("Sensor successfully scanned")
                                        }
                                        session.invalidate()
                                        
                                    }
                                }
                            }
                        }
                    }
                }
            }
            //                    }
            //                }
            //            }
        }
//    }
    }
    
    // MARK: - helper functions

    func readRaw(_ address: UInt16, _ bytes: Int, buffer: Data = Data(), tag: NFCISO15693Tag, handler: @escaping (UInt16, Data, Error?) -> Void) {
        
        var buffer = buffer
        let addressToRead = address + UInt16(buffer.count)
        
        var remainingBytes = bytes
        let bytesToRead = remainingBytes > 24 ? 24 : bytes
        
        var remainingWords = bytes / 2
        if bytes % 2 == 1 || ( bytes % 2 == 0 && addressToRead % 2 == 1 ) { remainingWords += 1 }
        let wordsToRead = UInt8(remainingWords > 12 ? 12 : remainingWords)    // real limit is 15
        
        // this is for libre 2 only, ignoring other libre types
        let readRawCommand = NFCCommand(code: 0xB3, parameters: Data([UInt8(addressToRead & 0x00FF), UInt8(addressToRead >> 8), wordsToRead]))
        
        if buffer.count == 0 {
            xdrip.trace("NFC: sending 0x%{public}@ 0x07 0x%{public}@ command (%{public}@ read raw)", log: log, category: ConstantsLog.categoryLibreNFC, type: .info, readRawCommand.code.description, readRawCommand.parameters.toHexString(), "libre 2")
        }

        tag.customCommand(requestFlags: .highDataRate, customCommandCode: Int(readRawCommand.code), customRequestParameters: readRawCommand.parameters) {
            
            response, error in
            
            var data = response
            
            if error != nil {
                
                xdrip.trace("NFC: error while reading %{public}@ words at raw memory 0x%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, wordsToRead.description, addressToRead.description)

                remainingBytes = 0
                
            } else {
                if addressToRead % 2 == 1 { data = data.subdata(in: 1 ..< data.count) }
                if data.count - Int(bytesToRead) == 1 { data = data.subdata(in: 0 ..< data.count - 1) }
            }
            
            buffer += data
            remainingBytes -= data.count
            
            if remainingBytes == 0 {
                handler(address, buffer, error)
            } else {
                self.readRaw(address, remainingBytes, buffer: buffer, tag: tag) { address, data, error in handler(address, data, error) }
            }
        }
    }

    func writeRaw(_ address: UInt16, _ data: Data, tag: NFCISO15693Tag, handler: @escaping (UInt16, Data, Error?) -> Void) {
        
        let backdoor = "deadbeef".bytes
        
        // Unlock
        xdrip.trace("NFC: sending 0xa4 0x07 0x%{public}@ command (%{public}@ unlock)", log: log, category: ConstantsLog.categoryLibreNFC, type: .info, Data(backdoor).toHexString(), "libre 2")

        tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA4, customRequestParameters: Data(backdoor)) {
            
            response, error in
            
            xdrip.trace("NFC: unlock command response: 0x%{public}@, error: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, response.toHexString(), error?.localizedDescription ?? "none")
            
            let addressToRead = (address / 8) * 8
            let startOffset = Int(address % 8)
            let endAddressToRead = ((Int(address) + data.count - 1) / 8) * 8 + 7
            let blocksToRead = (endAddressToRead - Int(addressToRead)) / 8 + 1
            
            self.readRaw(addressToRead, blocksToRead * 8, tag: tag) { readAddress, readData, error in

                var msg = error?.localizedDescription ?? readData.hexDump(address: Int(readAddress), header: "NFC: blocks to overwrite:")
                
                if error != nil {
                    handler(address, data, error)
                    return
                }
                
                var bytesToWrite = readData
                bytesToWrite.replaceSubrange(startOffset ..< startOffset + data.count, with: data)
                msg += "\(bytesToWrite.hexDump(address: Int(addressToRead), header: "\nwith blocks:"))"
                
                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, msg)
                
                let startBlock = Int(addressToRead / 8)
                let blocks = bytesToWrite.count / 8
                
                if address < 0xF860 { // lower than FRAM blocks
                    
                    for i in 0 ..< blocks {
                        
                        let blockToWrite = bytesToWrite[i * 8 ... i * 8 + 7]
                        
                        // FIXME: doesn't work as the custom commands C1 or A5 for other chips
                        tag.extendedWriteSingleBlock(requestFlags: .highDataRate, blockNumber: startBlock + i, dataBlock: blockToWrite) { error in

                            var debugInfo = String(format: "%X", startBlock + i) + " " + Int(i + 1).description + " of " + blocks.description + " " + blockToWrite.toHexString() + " at 0x" + String(format: "%X", Int((startBlock + i) * 8))
                            
                            if let error = error {
                                
                                debugInfo = "NFC: error while writing block 0x" + debugInfo + " : " + error.localizedDescription
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                                if i != blocks - 1 { return }
                                
                            } else {

                                debugInfo = "NFC: wrote block 0x" + debugInfo
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                            }
                            
                            if i == blocks - 1 {
                                
                                // Lock
                                tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA2, customRequestParameters: Data(backdoor)) { response, error in
                                    
                                    xdrip.trace("NFC: lock command response: 0x%{public}@, error: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, response.toHexString(), error?.localizedDescription ?? "none")
                                    
                                    handler(address, data, error)
                                    
                                }
                                
                            }
                        }
                    }
                    
                } else { // address >= 0xF860: write to FRAM blocks
                    
                    let requestBlocks = 2    // 3 doesn't work
                    
                    let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
                    let remainder = blocks % requestBlocks
                    var blocksToWrite = [Data](repeating: Data(), count: blocks)
                    
                    for i in 0 ..< blocks {
                        blocksToWrite[i] = Data(bytesToWrite[i * 8 ... i * 8 + 7])
                    }
                    
                    for i in 0 ..< requests {
                        
                        let startIndex = startBlock - 0xF860 / 8 + i * requestBlocks
                        let endIndex = startIndex + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)
                        let blockRange = NSRange(UInt8(startIndex) ... UInt8(endIndex))
                        
                        var dataBlocks = [Data]()
                        for j in startIndex ... endIndex { dataBlocks.append(blocksToWrite[j - startIndex]) }
                        
                        // TODO: write to 16-bit addresses as the custom cummand C4 for other chips
                        tag.writeMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: blockRange, dataBlocks: dataBlocks) {
                            
                            error in // TEST

                            var debugInfo = String(format: "%X", startIndex) + " - 0x" + String(format: "%X", endIndex) +  dataBlocks.reduce("", { $0 + $1.toHexString() }) + " at 0x" + String(format: "%X", (startBlock + i * requestBlocks) * 8)

                            if error != nil {
                                
                                debugInfo = "NFC: error while writing multiple blocks 0x" + debugInfo + " : " + error!.localizedDescription
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                
                                if i != requests - 1 { return }
                                
                            } else {
                                
                                debugInfo = "NFC: wrote blocks 0x" + debugInfo
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                
                            }
                            
                            if i == requests - 1 {
                                
                                // Lock
                                tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA2, customRequestParameters: Data(backdoor)) {
                                    
                                    response, error in
                                    
                                    let debugInfo = "NFC: lock command response: 0x" + response.toHexString() +  "error: " + (error?.localizedDescription ?? "none")
                                    
                                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                    
                                    handler(address, data, error)
                                }
                            }
                        } // TEST writeMultipleBlocks
                    }
                }
            }
        }
    }

    private func trace(systemError: Error?, ownErrorString: String, invalidateSession: Bool, session: NFCTagReaderSession) {
        
        if let systemError = systemError {

            xdrip.trace("NFC: error : %{public}@", log: log, category: ConstantsLog.categoryLibreNFC, type: .info, systemError.localizedDescription)

        }

        if invalidateSession {
            
            xdrip.trace("   will invalidate session", log: log, category: ConstantsLog.categoryLibreNFC, type: .info)

//            session.invalidate(errorMessage: "\(ownErrorString) : \(systemError != nil ? systemError!.localizedDescription : "")")
            session.invalidate(errorMessage: "Sensor scan error")
            
        }
        
    }
    
    private func traceICIdentifier(tag : NFCISO15693Tag) {
        
        xdrip.trace("NFC: IC identifier: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, tag.identifier.toHexString())
        
    }
   
    private func traceICManufacturer(tag : NFCISO15693Tag) {

        var manufacturer = String(tag.icManufacturerCode)
        if manufacturer == "7" {
            manufacturer.append(" (Texas Instruments)")
        }

        xdrip.trace("NFC: IC manufacturer code: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, manufacturer)
        
    }
    
    private func traceICSerialNumber(tag : NFCISO15693Tag) {
        
        xdrip.trace("NFC: IC serial number: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, tag.icSerialNumber.toHexString())
        
    }

    private func traceROM(tag : NFCISO15693Tag) {

        var rom = "RF430"
        switch tag.identifier[2] {
        case 0xA0: rom += "TAL152H Libre 1 A0"
        case 0xA4: rom += "TAL160H Libre 2 A4"
        default:   rom += " unknown"
        }

        xdrip.trace("NFC: %{public}@ ROM", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, rom)
        
    }
    
    private func traceICReference(systemInfo: NFCISO15693SystemInfo) {
        
        xdrip.trace("NFC: IC reference: 0x%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.icReference.description)

    }
    
    private func traceApplicationFamilyIdentifier(systemInfo: NFCISO15693SystemInfo) {
        
        if systemInfo.applicationFamilyIdentifier != -1 {
            
            xdrip.trace("NFC: application family id (AFI): %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.applicationFamilyIdentifier.description)
            
        }

    }

    private func traceDataStorageFormatIdentifier(systemInfo: NFCISO15693SystemInfo) {
     
        if systemInfo.dataStorageFormatIdentifier != -1 {
            
            xdrip.trace("NFC: data storage format id: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.dataStorageFormatIdentifier.description)
            
        }

    }
    
    private func traceMemorySize(systemInfo: NFCISO15693SystemInfo) {
        
            xdrip.trace("NFC: memory size: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.totalBlocks.description)
            
    }
    
    private func traceBlockSize(systemInfo: NFCISO15693SystemInfo) {
        
        xdrip.trace("NFC: block size: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.blockSize.description)
        
    }
    
    private func traceSensorUID(sensorUID: Data) {
        
        xdrip.trace("NFC: sensorUID: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, sensorUID.toHexString())
        
    }
    
    private func tracePatchInfo(patchInfo: Data) {
        
        xdrip.trace("NFC: patchInfo: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, patchInfo.toHexString())
        
    }
    
    private func nfcCommand(_ code: Subcommand, unlockCode: UInt32, patchInfo: Data, sensorUID: Data) -> NFCCommand {
        
        var b: [UInt8] = []
        var y: UInt16
        
        if code == .enableStreaming {
            
            // Enables Bluetooth on Libre 2. Returns peripheral MAC address to connect to.
            // unlockCode could be any 32 bit value. The unlockCode and sensor Uid / patchInfo
            // will have also to be provided to the login function when connecting to peripheral.
            
            b = [
                UInt8(unlockCode & 0xFF),
                UInt8((unlockCode >> 8) & 0xFF),
                UInt8((unlockCode >> 16) & 0xFF),
                UInt8((unlockCode >> 24) & 0xFF)
            ]
            
            y = UInt16(patchInfo[4...5]) ^ UInt16(b[1], b[0])
            
        } else {
            y = 0x1b6a
        }
        
        let d = PreLibre2.usefulFunction(sensorUID: sensorUID, x: UInt16(code.rawValue), y: y)
        
        var parameters = Data([code.rawValue])
        
        if code == .enableStreaming {
            parameters += b
        }
        
        parameters += d
        
        return NFCCommand(code: 0xA1, parameters: parameters)
        
    }
    
}

#endif
