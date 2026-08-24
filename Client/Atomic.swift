//
// Copyright (C) 2026 Wenyi Chen

//  Atomic.swift
//  AR_demo2
//
//  Created by Wenyi on 17/03/2025.
//

import Foundation
import CoreLocation
import CoreMotion

class AtomicVariable<T> {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func update(_ transform: (T) -> T) {
        lock.lock()
        defer { lock.unlock() }
        value = transform(value)
    }
}

class AtomicLocation {
    
    private var value:CLLocation?
    private let lock = NSLock()
   

    init() {
        self.value = nil
    }

    func getLat() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value!.coordinate.latitude
    }
    
    func getLon() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value!.coordinate.longitude
    }
    
    func getAlt() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value!.altitude
    }
    
    func getLocation() -> (lat:Double, lon:Double, alt:Double){
        lock.lock()
        defer { lock.unlock() }
        return (value!.coordinate.latitude, value!.coordinate.longitude, value!.altitude)
    }
    
    
    func getHorizontalAccuracy() -> Double{
        lock.lock()
        defer { lock.unlock() }
        
        return value!.horizontalAccuracy
    }
    
    func getVerticalAccuracy() -> Double{
        lock.lock()
        defer { lock.unlock() }
        
        return value!.verticalAccuracy
    }

    func set_location(_ newValue: CLLocation) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
    

    func isNil() -> Bool{
        lock.lock()
        defer { lock.unlock() }
        return self.value == nil
    }
    
    func get() -> CLLocation? {
        lock.lock()
        defer { lock.unlock() }

        return value
    }
}

class AtomicHeading {
    
    private var heading:CLHeading?
    private let lock = NSLock()
    
    func set_heading(_ newValue: CLHeading) {
        lock.lock()
        defer { lock.unlock() }
        heading = newValue
    }
    
    func getHeadigDegree ()-> Double{
        lock.lock()
        defer { lock.unlock() }

        return heading!.trueHeading
    }
    
    func isNil() -> Bool{
        lock.lock()
        defer { lock.unlock() }
        return self.heading == nil
    }
    
    
}

class AtomicMotion {
    
    private var value:CMDeviceMotion?
    private let lock = NSLock()

    init() {
        self.value = nil
    }
    
    func isNil() -> Bool{
        lock.lock()
        defer { lock.unlock() }
        return self.value == nil
    }

    func getYaw() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value!.attitude.yaw
    }
    
    func getPitch() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value!.attitude.pitch
    }
    
    func getRoll() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value!.attitude.roll
    }
    
    func getHeading() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value!.heading
    }
    

    

    func set_motion(_ newValue: CMDeviceMotion) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
    
    
}

class AtomicCounter {
    
    private var value:Int?
    private let lock = NSLock()
    
    
    func increment (){
        lock.lock()
        
        if value == nil {
            value = 1
        } else {
            value! += 1
        }
        
        lock.unlock()
        
    }
    
    func decrement (){
        lock.lock()
        
        if value == nil || value == 0 {
           // do nothing
        } else {
            value! -= 1
        }
        
        lock.unlock()
        
    }
    
    func reset () {
        lock.lock()
        value = nil
        lock.unlock()
    }
    
    func set_value (new_value:Int){
        lock.lock()
        value = new_value
        lock.unlock()
    }
    
    func get_value() -> Int {
        lock.lock()
        defer { lock.unlock() }

        return value ?? -1
    }
    
    
}



class AtomicArray<Element> {
    internal var array: [Element] = []
    internal let lock = NSLock()
    
   
    func append(_ newElement: Element) {
        lock.lock()
        array.append(newElement)
        lock.unlock()
    }
    
   
    var count: Int {
        lock.lock()
        let count = array.count
        lock.unlock()
        return count
    }
    
   
    func element(at index: Int) -> Element? {
        lock.lock()
        let element = array.indices.contains(index) ? array[index] : nil
        lock.unlock()
        return element
    }
    
  
    var value: [Element] {
        lock.lock()
        let copy = array
        lock.unlock()
        return copy
    }
    
    
    // remove element by index (if exists)
    @discardableResult
    func remove(at index: Int) -> Element? {
        lock.lock()
        defer { lock.unlock() }
        guard array.indices.contains(index) else {
            return nil
        }
        return array.remove(at: index)
    }
    

    func removeAll() {
        lock.lock()
        array.removeAll()
        lock.unlock()
    }
    
    
    
    func forEach(_ body: (Element) -> Void) {
        lock.lock()
        let snapshot = array
        lock.unlock()
        snapshot.forEach { body($0) }
    }
    
    // how to call:
    // atomicIntArray.forEach { element in
    //   print(element)
    // }
}

class AtomicAnchorInformation: AtomicArray<Anchor_information> {
    
    func contain(id:UUID) -> Bool{
        lock.lock()
        
        defer {
            lock.unlock()
        }
        
        for anchor in self.array{
            if anchor.anchor_id == id {
                return true
            }
        }
        
        return false

    }
    
    
}

class AtomicAnchorStatus: AtomicVariable<Int> {
    override init(_ initialValue: Int = 0) {
        super.init(initialValue)
    }
}
