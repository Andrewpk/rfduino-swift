//
//  RFDuino.swift
//  Pods
//
//  Created by Jordy van Kuijk on 27/01/16.
//
//

import Foundation
import CoreBluetooth

@objc public protocol RFDuinoDelegate {
    @objc optional func rfDuinoDidTimeout(_ rfDuino: RFDuino)
    @objc optional func rfDuinoDidDisconnect(_ rfDuino: RFDuino)
    @objc optional func rfDuinoDidDiscover(_ rfDuino: RFDuino)
    @objc optional func rfDuinoDidDiscoverServices(_ rfDuino: RFDuino)
    @objc optional func rfDuinoDidDiscoverCharacteristics(_ rfDuino: RFDuino)
    @objc optional func rfDuinoDidSendData(_ rfDuino: RFDuino, forCharacteristic: CBCharacteristic, error: NSError?)
    @objc optional func rfDuinoDidReceiveData(_ rfDuino: RFDuino, data: Data?)
}

open class RFDuino: NSObject {
    
    open var isTimedOut = false
    open var isConnected = false
    open var didDiscoverCharacteristics = false
    
    open var delegate: RFDuinoDelegate?
    open static let timeoutThreshold = 5.0
    open var RSSI: NSNumber?
    
    var whenDoneBlock: (() -> ())?
    var peripheral: CBPeripheral
    var timeoutTimer: Timer?
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self
    }
}

/* Internal methods */
internal extension RFDuino {
    func confirmAndTimeout() {
        isTimedOut = false
        delegate?.rfDuinoDidDiscover?(self)
        
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        timeoutTimer = Timer.scheduledTimer(timeInterval: RFDuino.timeoutThreshold, target: self, selector: #selector(RFDuino.didTimeout), userInfo: nil, repeats: false)
    }
    
    func didTimeout() {
        isTimedOut = true
        isConnected = false
        delegate?.rfDuinoDidTimeout?(self)
    }
    
    func didConnect() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        isConnected  = true
        isTimedOut = false
    }
    
    func didDisconnect() {
        isConnected = false
        confirmAndTimeout()
        delegate?.rfDuinoDidDisconnect?(self)
    }
    
    func findCharacteristic(characteristicUUID: RFDuinoUUID, forServiceWithUUID serviceUUID: RFDuinoUUID) -> CBCharacteristic? {
        if let discoveredServices = peripheral.services,
            let service = (discoveredServices.filter { return $0.uuid == serviceUUID.id }).first,
            let characteristics = service.characteristics {
            return (characteristics.filter { return $0.uuid ==  characteristicUUID.id}).first
        }
        return nil
    }
}

/* Public methods */
public extension RFDuino {
    func discoverServices() {
        "Going to discover services for peripheral".log()
        peripheral.discoverServices([RFDuinoUUID.Discover.id])
    }
    
    func sendDisconnectCommand(_ whenDone: @escaping () -> ()) {
        self.whenDoneBlock = whenDone
        // if no services were discovered, imediately invoke done block
        if peripheral.services == nil {
            whenDone()
            return
        }
        if let characteristic = findCharacteristic(characteristicUUID: RFDuinoUUID.Disconnect, forServiceWithUUID: RFDuinoUUID.Discover) {
            var byte = UInt8(1)
            let data = withUnsafeMutablePointer(to: &byte, {
                Data(bytes: UnsafePointer($0), count: MemoryLayout.size(ofValue: byte))
            })
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    func send(_ data: Data) {
        if let characteristic = findCharacteristic(characteristicUUID: RFDuinoUUID.Send, forServiceWithUUID: RFDuinoUUID.Discover) {
        	peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
}

/* Calculated vars */
public extension RFDuino {
    var name: String {
        get {
            return peripheral.name ?? "Unknown device"
        }
    }
}

extension RFDuino: CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        "Did send data to peripheral".log()
        
        if characteristic.uuid == RFDuinoUUID.Disconnect.id {
            if let doneBlock = whenDoneBlock {
                doneBlock()
            }
        } else {
            delegate?.rfDuinoDidSendData?(self, forCharacteristic: self.findCharacteristic(characteristicUUID: RFDuinoUUID.Send, forServiceWithUUID: RFDuinoUUID.Discover)!, error: error as NSError?)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        "Did discover services".log()
        if let discoveredServices = peripheral.services {
            for service in discoveredServices {
                if service.uuid == RFDuinoUUID.Discover.id {
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
        }
        delegate?.rfDuinoDidDiscoverServices?(self)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        for characteristic in service.characteristics! {
            ("did discover characteristic with UUID: " + characteristic.uuid.description).log()
            if characteristic.uuid == RFDuinoUUID.Receive.id {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == RFDuinoUUID.Send.id {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        
        "Did discover characteristics for service".log()
        delegate?.rfDuinoDidDiscoverCharacteristics?(self)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        "Did receive data for rfDuino".log()
        delegate?.rfDuinoDidReceiveData?(self, data: characteristic.value)
    }
}
