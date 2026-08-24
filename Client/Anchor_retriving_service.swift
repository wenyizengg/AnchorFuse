//
// Copyright (C) 2026 Wenyi Chen

//  Anchor_retriving_service.swift
//  AR_demo2
//
//  Created by Wenyi on 17/03/2025.
//

import Foundation
import UIKit
import Network
import ARKit
import RealityKit
import simd
class Anchor_retriving_service{
    
    var connection: NWConnection
    
    // Number of nearby anchors
    var total_amount = AtomicCounter()
    
    weak var coordinator: Coordinator?
    
    private let connectionQueue = DispatchQueue(
        label: "AnchorRetrievingService.connection"
    )

    private var connected_to_server = false
    private var pollInFlight = false
    

    init(host:String, port:UInt16, coordinator:Coordinator){
        
        
        self.connection = NWConnection(host: NWEndpoint.Host(host),port: NWEndpoint.Port(rawValue: port)!, using:.tcp)
        

        self.coordinator = coordinator
        
        self.start_connection()
        
        

        
    }
    
    func start_connection() {

        connection.stateUpdateHandler = { [weak self] state in

            guard let self else {
                return
            }

            switch state {

            case .ready:
                print("GPS service connected to server.")

                self.connected_to_server = true
                self.schedule_location_send(after: 0)

            case .failed(let error):
                print("Connection failed: \(error)")

                self.connected_to_server = false
                self.pollInFlight = false

            case .waiting(let error):
                print("Connection waiting: \(error)")

                self.connected_to_server = false
                self.pollInFlight = false

            case .cancelled:
                print("Connection cancelled.")

                self.connected_to_server = false
                self.pollInFlight = false

            case .setup:
                print("Setting up connection.")

            default:
                break
            }
        }

        connection.start(queue: connectionQueue)
    }
    
    
    
    func send_location() {

        guard connected_to_server else {
            schedule_location_send(after: 1)
            return
        }

        guard !pollInFlight else {
            return
        }

        guard let coordinator,
              let location = coordinator.currentLocation.get() else {

            schedule_location_send(after: 1)
            return
        }

        print(
            "Lat: \(location.coordinate.latitude), "
            + "Lon: \(location.coordinate.longitude), "
            + "Altitude: \(location.altitude)"
        )

        pollInFlight = true

        send_current_location(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            alt: location.altitude
        )
    }
    
    
    func send_current_location(lat:Double, lon:Double, alt:Double){

        var package_ = Data()
        package_.append(contentsOf: lon.toBytes())
        package_.append(contentsOf: lat.toBytes())
        package_.append(contentsOf: alt.toBytes())
        
        connection.send(content: package_, completion: .contentProcessed { error in
            
            if let error {
                print("Failed to send data: \(error.localizedDescription)")
                self.pollInFlight = false
                self.schedule_location_send(after: 1)
                return
            } else {
                print("Data sent successfully!")
                
               self.receive_header()
                
            }
        })
        
    }
    
    func receive_header() {

        connection.receive(
            minimumIncompleteLength: 4,
            maximumLength: 4
        ) { [weak self] content, _, _, error in

            guard let self else {
                return
            }

            guard error == nil,
                  let content,
                  content.count == 4 else {

                print(
                    "Failed receiving anchor count: "
                    + "\(error?.localizedDescription ?? "invalid size")"
                )

                self.finish_poll_cycle()
                return
            }

            let rawCount: UInt32 = content.withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self)
            }

            let anchorCount = UInt32(
                littleEndian: rawCount
            )

            self.total_amount.set_value(
                new_value: Int(anchorCount)
            )

            print("Number of nearby anchors: \(anchorCount)")

            self.receive_nearby_anchors()
        }
    }
    
    
    func receive_nearby_anchors() {

        guard let coordinator = coordinator,
              total_amount.get_value() != -1 else {
            return
        }

        if total_amount.get_value() == 0 {

            finish_poll_cycle()
            return
        }

        // Receive the fixed size 72 byte anchor header.
        connection.receive(
            minimumIncompleteLength: 72,
            maximumLength: 72
        ) {
            content,
            contentContext,
            isComplete,
            error in

            guard let headerData = content,
                  headerData.count == 72 else {

                if let error {
                    print(
                        "Error receiving anchor header: " +
                        "\(error.localizedDescription)"
                    )
                } else {
                    print(
                        "Wrong header size. Expected 72 bytes, " +
                        "received \(content?.count ?? 0)."
                    )
                }

                self.finish_poll_cycle()
                return
            }

            // Parse the first 72 bytes.
            let uuid = headerData
                .subdata(in: 0..<16)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: uuid_t.self)
                }

            let id = UUID(uuid: uuid)

            let model_id: Int32 = headerData
                .subdata(in: 16..<20)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Int32.self)
                }

            let lon: Double = headerData
                .subdata(in: 20..<28)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Double.self)
                }

            let lat: Double = headerData
                .subdata(in: 28..<36)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Double.self)
                }

            let alt: Double = headerData
                .subdata(in: 36..<44)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Double.self)
                }

            let yaw: Double = headerData
                .subdata(in: 44..<52)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Double.self)
                }

            let pitch: Double = headerData
                .subdata(in: 52..<60)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Double.self)
                }

            let roll: Double = headerData
                .subdata(in: 60..<68)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Double.self)
                }

            let binary_field_size: Int32 = headerData
                .subdata(in: 68..<72)
                .withUnsafeBytes {
                    $0.loadUnaligned(as: Int32.self)
                }

            print("\n")
            print("ID: \(id)")
            print(
                "Model ID: \(model_id), " +
                "lon: \(lon), lat: \(lat), alt: \(alt), " +
                "yaw: \(yaw), pitch: \(pitch), roll: \(roll), " +
                "binary field size: \(binary_field_size)"
            )
            print("\n")

            guard binary_field_size > 0 else {
                print(
                    "Invalid binary field size: \(binary_field_size)."
                )

                self.total_amount.decrement()
                self.receive_nearby_anchors()
                return
            }

            let expectedPayloadSize = Int(binary_field_size)

            // Receive the visual payload.
            self.connection.receive(
                minimumIncompleteLength: expectedPayloadSize,
                maximumLength: expectedPayloadSize
            ) {
                content,
                contentContext,
                isComplete,
                error in

                guard let payloadData = content,
                      payloadData.count == expectedPayloadSize else {

                    if let error {
                        print(
                            "Error receiving anchor payload: " +
                            "\(error.localizedDescription)"
                        )
                    } else {
                        print(
                            "Wrong binary payload size. " +
                            "Expected \(expectedPayloadSize), " +
                            "received \(content?.count ?? 0)."
                        )
                    }

                    self.total_amount.decrement()
                    self.receive_nearby_anchors()
                    return
                }

                guard let anchor = self.parse_binary_data(
                    package: payloadData,
                    id: id,
                    model_id: model_id,
                    lon: lon,
                    lat: lat,
                    alt: alt,
                    yaw: yaw,
                    pitch: pitch,
                    roll: roll
                ) else {
                    print(
                        "Failed to parse received anchor \(id)."
                    )

                    self.total_amount.decrement()
                    self.receive_nearby_anchors()
                    return
                }

                if !coordinator.nearby_anchors.contain(
                    id: anchor.anchor_id
                ) {
                    coordinator.nearby_anchors.append(anchor)
                }

                self.total_amount.decrement()
                self.receive_nearby_anchors()
            }
        }
    }
    
    
    func parse_binary_data(
        package: Data,
        id: UUID,
        model_id: Int32,
        lon: Double,
        lat: Double,
        alt: Double,
        yaw: Double,
        pitch: Double,
        roll: Double
    ) -> Anchor_information? {

        print("PnP binary field size passed in: \(package.count)")

        guard !package.isEmpty else {
            print("Cannot parse visual payload: package is empty.")
            return nil
        }

        var offset = 0

        // MARK: Number of keyframes

        let amount = Int(package[package.startIndex])
        offset += MemoryLayout<UInt8>.size

        guard amount > 0 else {
            print("Cannot parse visual payload: keyframe count is zero.")
            return nil
        }

        var anchorRelativeTransforms: [simd_float4x4] = []
        var landmarkPoints: [Data] = []
        var landmarkDescriptors: [Data] = []

        anchorRelativeTransforms.reserveCapacity(amount)
        landmarkPoints.reserveCapacity(amount)
        landmarkDescriptors.reserveCapacity(amount)

        let matrixByteSize = 16 * MemoryLayout<Float>.size
        let bytesPerPoint = 3 * MemoryLayout<Float>.size
        let bytesPerORBDescriptor = 32

        // MARK: Per-keyframe metric map

        for keyframeIndex in 0..<amount {

            guard offset + matrixByteSize <= package.count else {
                print(
                    "Cannot parse keyframe \(keyframeIndex): " +
                    "missing ^K T_A matrix."
                )
                return nil
            }

            let matrixData = package.subdata(
                in: offset..<(offset + matrixByteSize)
            )
            offset += matrixByteSize

            let matrices = parse4x4Matrices(
                from: matrixData,
                amount: 1
            )

            guard let anchorRelativeTransform = matrices.first else {
                print(
                    "Cannot parse keyframe \(keyframeIndex): " +
                    "invalid ^K T_A matrix."
                )
                return nil
            }

            guard let landmarkCountRaw = readUInt32(
                from: package,
                at: offset
            ) else {
                print(
                    "Cannot parse keyframe \(keyframeIndex): " +
                    "missing landmark count."
                )
                return nil
            }
            offset += MemoryLayout<UInt32>.size

            let landmarkCount = Int(landmarkCountRaw)

            guard landmarkCount >= 6 else {
                print(
                    "Cannot parse keyframe \(keyframeIndex): " +
                    "too few metric landmarks (\(landmarkCount))."
                )
                return nil
            }

            let pointByteCount = landmarkCount * bytesPerPoint
            let descriptorByteCount =
                landmarkCount * bytesPerORBDescriptor

            guard offset + pointByteCount <= package.count else {
                print(
                    "Cannot parse keyframe \(keyframeIndex): " +
                    "truncated metric point data."
                )
                return nil
            }

            let pointData = package.subdata(
                in: offset..<(offset + pointByteCount)
            )
            offset += pointByteCount

            guard offset + descriptorByteCount <= package.count else {
                print(
                    "Cannot parse keyframe \(keyframeIndex): " +
                    "truncated ORB descriptor data."
                )
                return nil
            }

            let descriptorData = package.subdata(
                in: offset..<(offset + descriptorByteCount)
            )
            offset += descriptorByteCount

            anchorRelativeTransforms.append(anchorRelativeTransform)
            landmarkPoints.append(pointData)
            landmarkDescriptors.append(descriptorData)

            print(
                "Parsed keyframe \(keyframeIndex): " +
                "\(landmarkCount) metric landmarks."
            )
        }

        guard offset == package.count else {
            print(
                "Cannot parse PnP payload: \(package.count - offset) " +
                "unexpected trailing bytes remain."
            )
            return nil
        }

        return Anchor_information(
            anchor_id: id,
            model_id: model_id,
            lat: lat,
            lon: lon,
            alt: alt,
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            anchorRelativeTransforms: anchorRelativeTransforms,
            landmarkPoints: landmarkPoints,
            landmarkDescriptors: landmarkDescriptors
        )
    }


    func parse4x4Matrices(
        from data: Data,
        amount: Int
    ) -> [simd_float4x4] {

        let floatsPerMatrix = 16
        let matrixByteSize =
            floatsPerMatrix * MemoryLayout<Float>.size
        let expectedByteCount = amount * matrixByteSize

        guard data.count == expectedByteCount else {
            print(
                "Invalid 4×4 matrix data size. " +
                "Expected \(expectedByteCount), received \(data.count)."
            )
            return []
        }

        var matrices: [simd_float4x4] = []
        matrices.reserveCapacity(amount)

        for matrixIndex in 0..<amount {

            let matrixOffset = matrixIndex * matrixByteSize
            var values: [Float] = []
            values.reserveCapacity(floatsPerMatrix)

            for floatIndex in 0..<floatsPerMatrix {
                let floatOffset =
                    matrixOffset +
                    floatIndex * MemoryLayout<Float>.size

                guard let value = readFloat32(
                    from: data,
                    at: floatOffset
                ) else {
                    print(
                        "Failed reading 4×4 matrix \(matrixIndex), " +
                        "element \(floatIndex)."
                    )
                    return []
                }

                values.append(value)
            }

            let column0 = SIMD4<Float>(
                values[0], values[1], values[2], values[3]
            )
            let column1 = SIMD4<Float>(
                values[4], values[5], values[6], values[7]
            )
            let column2 = SIMD4<Float>(
                values[8], values[9], values[10], values[11]
            )
            let column3 = SIMD4<Float>(
                values[12], values[13], values[14], values[15]
            )

            matrices.append(
                simd_float4x4(
                    columns: (
                        column0,
                        column1,
                        column2,
                        column3
                    )
                )
            )
        }

        return matrices
    }


    private func readUnaligned<T>(
        _ type: T.Type,
        from data: Data,
        at offset: Int
    ) -> T? {

        let byteCount = MemoryLayout<T>.size

        guard offset >= 0,
              offset + byteCount <= data.count else {
            return nil
        }

        return data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(
                fromByteOffset: offset,
                as: T.self
            )
        }
    }


    private func readFloat32(
        from data: Data,
        at offset: Int
    ) -> Float? {

        guard let rawBits: UInt32 = readUnaligned(
            UInt32.self,
            from: data,
            at: offset
        ) else {
            return nil
        }

        return Float(
            bitPattern: UInt32(littleEndian: rawBits)
        )
    }


    private func readUInt32(
        from data: Data,
        at offset: Int
    ) -> UInt32? {

        guard let rawValue: UInt32 = readUnaligned(
            UInt32.self,
            from: data,
            at: offset
        ) else {
            return nil
        }

        return UInt32(littleEndian: rawValue)
    }


    private func schedule_location_send(
        after delay: TimeInterval = 1
    ) {
        connectionQueue.asyncAfter(
            deadline: .now() + delay
        ) { [weak self] in
            self?.send_location()
        }
    }


    private func finish_poll_cycle() {
        total_amount.reset()
        pollInFlight = false
        schedule_location_send(after: 1)
    }
}
