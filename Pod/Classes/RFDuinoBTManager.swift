//
//  RFDuinoBTManager.swift
//  Pods
//
//  Created by Jordy van Kuijk on 27/01/16.
//
//

import Foundation
import CoreBluetooth

@objc public protocol RFDuinoBTManagerDelegate {
    @objc optional func rfDuinoManagerDidDiscoverRFDuino(_ manager: RFDuinoBTManager, rfDuino: RFDuino)
    @objc optional func rfDuinoManagerDidConnectRFDuino(_ manager: RFDuinoBTManager, rfDuino: RFDuino)
}

public struct RFDuinoUUIDS {
    public static var discoverUUID: String?
    public static var disconnectUUID: String?
    public static var receiveUUID: String?
    public static var sendUUID: String?
}

internal enum RFDuinoUUID: String {
    case Discover = "2220"
    case Disconnect = "2221"
    case Receive = "2222"
    case Send = "2223"
    
    var id: CBUUID {
        get {
            switch self {
                case .Discover: return CBUUID(string: RFDuinoUUIDS.discoverUUID ?? self.rawValue)
                case .Disconnect: return CBUUID(string: RFDuinoUUIDS.disconnectUUID ?? self.rawValue)
                case .Receive: return CBUUID(string: RFDuinoUUIDS.receiveUUID ?? self.rawValue)
                case .Send: return CBUUID(string: RFDuinoUUIDS.sendUUID ?? self.rawValue)
            }
        }
    }
}

open class RFDuinoBTManager : NSObject {
    /* Public variables */
    open static let sharedInstance = RFDuinoBTManager()
    open var delegate: RFDuinoBTManagerDelegate?
    
    /* Private variables */
    lazy fileprivate var centralManager:CBCentralManager = {
        let manager = CBCentralManager(delegate: sharedInstance, queue: DispatchQueue.main)
        return manager
    }()
    fileprivate var reScanTimer: Timer?
    fileprivate static var reScanInterval = 3.0
    internal static var logging = false
    
    fileprivate var _discoveredRFDuinos: [RFDuino] = []
    open var discoveredRFDuinos: [RFDuino] = [] {
        didSet {
            if oldValue.count < discoveredRFDuinos.count {
                delegate?.rfDuinoManagerDidDiscoverRFDuino?(self, rfDuino: discoveredRFDuinos.last!)
            }
        }
    }
    
    override init() {
        super.init()
        "initialized RFDuinoBTRManager".log()
    }
}
    
/* Public methods */
public extension RFDuinoBTManager {
    
    func setLoggingEnabled(_ enabled: Bool) {
        RFDuinoBTManager.logging = enabled
    }
    
    func startScanningForRFDuinos() {
        "Started scanning for peripherals".log()
        centralManager.scanForPeripherals(withServices: [RFDuinoUUID.Discover.id], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScanningForRFDuinos() {
        discoveredRFDuinos = []
        "Stopped scanning for peripherals".log()
        centralManager.stopScan()
    }
    
    func connectRFDuino(_ rfDuino: RFDuino) {
        "Connecting to RFDuino".log()
        centralManager.connect(rfDuino.peripheral, options: nil)
    }
    
    func disconnectRFDuino(_ rfDuino: RFDuino) {
        "Disconnecting from RFDuino".log()
        rfDuino.sendDisconnectCommand { () -> () in
            DispatchQueue.main.async(execute: { () -> Void in
                self.centralManager.cancelPeripheralConnection(rfDuino.peripheral)
            })
        }
    }
    
    func disconnectRFDuinoWithoutSendCommand(_ rfDuino: RFDuino) {
        self.centralManager.cancelPeripheralConnection(rfDuino.peripheral)
    }
}

/* Internal methods */
extension RFDuinoBTManager {
    func reScan() {
        reScanTimer?.invalidate()
        reScanTimer = nil
        reScanTimer = Timer.scheduledTimer(timeInterval: RFDuinoBTManager.reScanInterval, target: self, selector: #selector(RFDuinoBTManager.startScanningForRFDuinos), userInfo: nil, repeats: true)
    }
}

extension RFDuinoBTManager : CBCentralManagerDelegate {
    
    /* Required delegate methods */
    @objc
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOff:
            "Bluetooth powered off".log()
        case .poweredOn:
            "Bluetooth powered on".log()
            startScanningForRFDuinos()
        case .resetting:
            "Bluetooth resetting".log()
        case.unauthorized:
            "Bluethooth unauthorized".log()
        case.unknown:
            "Bluetooth state unknown".log()
        case.unsupported:
            "Bluetooth unsupported".log()
        }
    }
    
    /* Optional delegate methods */
    @objc
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        "Did connect peripheral".log()
        if let rfDuino = discoveredRFDuinos.findRFDuino(peripheral) {
            rfDuino.didConnect()
            delegate?.rfDuinoManagerDidConnectRFDuino?(self, rfDuino: rfDuino)
        }
    }
    
    @objc
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        "Did disconnect peripheral".log()
        if let rfDuino = discoveredRFDuinos.findRFDuino(peripheral) {
            rfDuino.didDisconnect()
        }
    }
    
    @objc
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        "Did discover peripheral with name: \(peripheral.name ?? "")".log()
        discoveredRFDuinos.insertIfNotContained(RFDuino(peripheral: peripheral))
        let rfDuino = discoveredRFDuinos.findRFDuino(peripheral)
        rfDuino?.RSSI = RSSI
        reScan()
    }
    
    @objc
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        "Did fail to connect to peripheral".log()
    }
    
    @objc
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        "Will restore state".log()
    }
}

extension String {
    func log() {
        if RFDuinoBTManager.logging {
            print(" 📲 " + self)
        }
    }
}
