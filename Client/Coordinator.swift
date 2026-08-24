//
// Copyright (C) 2026 Wenyi Chen

//  Coordinator.swift
//  AR_demo2
//
//  Created by Wenyi on 09/03/2025.
//

import Foundation
import RealityKit
import SwiftUI
import ARKit
import CoreLocation
import CoreMotion
import Network
import simd



class Coordinator:NSObject, ARSessionDelegate {
    
    // MARK: Change this to the actual host IP address before running
    let host_address = "172.20.10.2"
    
    var arView:ARView?

    var onPlacementMethodChanged: ((AnchorPlacementMethod) -> Void)?

    var anchor_to_be_saved:ARAnchor?

    let locationManager = LocationManager()
    let motionManager = MotionManager()
    
    var currentTrueHeading = AtomicHeading()
    var currentLocation = AtomicLocation()
    var currentMotion = AtomicMotion()
    
    var nearby_anchors = AtomicAnchorInformation()
    
    //private let modelGravityAlignmentRollDegrees: Double = -90.0
    
    
    private var anchorTimer: Timer?
    
    private let placementQueue = DispatchQueue(
        label: "Coordinator.anchorPlacement",
        qos: .userInitiated
    )

    private let placementStateLock = NSLock()
    private var placementPassInProgress = false
    
    
    
    // ====================== Services =======================
    
    // lazy keyword means delayed initialisation, the code within {} will be executed after the initialisation of the rest of the class, which allows passing 'self' as a parameter.
    
    // MARK: NOTICE that if an object is marked as lazy, it WONT be initialised until the first access.
    
    lazy var anchor_saving_service: Anchor_saving_service = {
        return Anchor_saving_service(host:host_address, port:12347, coordinator:self)
    }()
    
    lazy var anchor_retriving_service: Anchor_retriving_service = {
        return Anchor_retriving_service(host:host_address, port:12345, coordinator:self)
    }()
    
    
    lazy var gps_preview_module = GPS_preview_module(coordinator:self)
    lazy var visual_localisation_module = Visual_localisation_module(coordinator: self)
    
    override init() {
        super.init()

        locationManager.onLocationUpdate = { [weak self] location in
            self?.currentLocation.set_location(location)
            print("Location updated")
        }

        locationManager.onHeadingUpdate = { [weak self] heading in
            self?.currentTrueHeading.set_heading(heading)
        }

        motionManager.onMotionUpdate = { [weak self] motion in
            self?.currentMotion.set_motion(motion)
        }

        anchorTimer = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(runPlaceAnchor),
            userInfo: nil,
            repeats: true
        )

        _ = anchor_saving_service
        _ = anchor_retriving_service
    }
    
    @objc private func runPlaceAnchor() {

        placementStateLock.lock()

        guard !placementPassInProgress else {
            placementStateLock.unlock()
            return
        }

        placementPassInProgress = true
        placementStateLock.unlock()

        placementQueue.async { [weak self] in

            guard let self else {
                return
            }

            defer {
                self.placementStateLock.lock()
                self.placementPassInProgress = false
                self.placementStateLock.unlock()
            }

            self.attempt_place_anchor_GPS()
            self.attempt_place_anchor_visual()
        }
    }
       
   deinit {
       // invalidate the timer when coordinator object is released
       anchorTimer?.invalidate()
   }
    
    
   
    @objc func tapping(_ recognizer:UITapGestureRecognizer){
        
        guard let arView = arView else {
            return
        }
        
        let location = recognizer.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
        
        if let result=results.first{
            
           
            let arAnchor = ARAnchor(name: UUID().uuidString, transform: result.worldTransform)
           // print("result world transform: \(result.worldTransform)")
            
            
            self.place_anchor_to_session(arAnchor: arAnchor)
            self.anchor_to_be_saved = arAnchor
            
        }
        
        
    }
    
    func capture() -> Bool{
        print("\n\n Entered capture()")
        guard let anchor = self.anchor_to_be_saved else {return false}
        print("\n\n passed guard()")
        
        return self.visual_localisation_module.capture(anchor:anchor)
    }
    
    
    
    func check_anchor_saving_condition()->Bool {
        
        if anchor_to_be_saved == nil {
            return false
        }
        
        return true
    }
    
    func save_anchor(
        completion: @escaping (Bool) -> Void
    ) {

        guard let anchor = anchor_to_be_saved else {
            completion(false)
            return
        }

        // currentMotion is not needed because pitch and roll are fixed.
        guard !currentLocation.isNil(),
              !currentTrueHeading.isNil() else {

            print("Location or true heading is unavailable.")
            completion(false)
            return
        }

        guard let anchorIDString = anchor.name,
              let anchorUUID = UUID(uuidString: anchorIDString) else {

            print("Anchor name does not contain a valid UUID.")
            completion(false)
            return
        }

        let gpsOutput = gps_preview_module.on_save()

        guard gpsOutput.valid else {
            print("GPS preview module returned invalid output.")
            completion(false)
            return
        }

        let visualKeyframeCount =
            visual_localisation_module.anchorRelativeTransforms.count

        guard visualKeyframeCount == 5,
              visual_localisation_module.landmarkPoints.count == visualKeyframeCount,
              visual_localisation_module.landmarkDescriptors.count == visualKeyframeCount else {
            print(
                "Anchor save rejected: five complete LiDAR/PnP keyframes " +
                "are required."
            )
            completion(false)
            return
        }

        let anchorInfo = Anchor_information(
            anchor_id: anchorUUID,
            model_id: 1,
            lat: gpsOutput.anchorLat,
            lon: gpsOutput.anchorLon,
            alt: gpsOutput.anchorAlt,
            yaw: gpsOutput.anchorYaw,
            pitch: 0,
            roll: 0,
            anchorRelativeTransforms:
                visual_localisation_module.anchorRelativeTransforms,
            landmarkPoints:
                visual_localisation_module.landmarkPoints,
            landmarkDescriptors:
                visual_localisation_module.landmarkDescriptors
        )

        anchor_saving_service.save_anchor(
            anchor_info: anchorInfo
        ) { [weak self] success in

            guard let self else {
                completion(false)
                return
            }

            if success {
                self.anchor_to_be_saved = nil
                self.visual_localisation_module.cleanup()
                print("Anchor send completed.")
            }

            completion(success)
        }
    }
    
    
    func attempt_place_anchor_visual() {

        let anchors = nearby_anchors.value

        guard !anchors.isEmpty else {
            return
        }

        for anchorInfo in anchors {

            guard anchorInfo.status.get() != 2 else {
                continue
            }

            let result = visual_localisation_module.find_overlap(
                anchor_info: anchorInfo
            )

            guard result.is_overlap else {
                continue
            }

            remove_anchor(id: anchorInfo.anchor_id)

            let arAnchor = ARAnchor(
                name: anchorInfo.anchor_id.uuidString,
                transform: result.Transform
            )

            place_anchor_to_session(arAnchor: arAnchor)
            anchorInfo.status.set(2)
            reportPlacementMethod(.visualLocalisation)
        }
    }
   
    
    func attempt_place_anchor_GPS(){
       
        guard self.nearby_anchors.count != 0 else {return}

        
        for i in 0..<nearby_anchors.count{
            
            if let anchor = nearby_anchors.element(at: i){
                
                if anchor.status.get() != 0 {
                    
                    continue
                    
                } else {
                    
                    let output = gps_preview_module.on_place(anchor: anchor)
                    
                    if (output.valid){
                        
                        let arAnchor = ARAnchor(name:anchor.anchor_id.uuidString, transform: output.Transform)
                        
                        self.place_anchor_to_session(arAnchor: arAnchor)
                        anchor.status.set(1)
                        self.reportPlacementMethod(.gpsEstimate)
                        
                    }
                    

                }

            }

          }

    }
    
    private func reportPlacementMethod(_ method: AnchorPlacementMethod) {
        DispatchQueue.main.async { [weak self] in
            self?.onPlacementMethodChanged?(method)
        }
    }

    func place_anchor_to_session(arAnchor:ARAnchor){
        
        guard let av = self.arView else {return}
        
        DispatchQueue.main.async {
            
            print(arAnchor.transform)
            
            let anchorEntity = AnchorEntity(anchor: arAnchor)
            anchorEntity.name = arAnchor.name ?? ""
            
          
            let model = ModelEntity(
                mesh: .generateBox(size: 0.5),
                    materials: [SimpleMaterial(color: .red, roughness: 0.15, isMetallic: true)]
            )
            
//            let model = self.loadModel(model_name: "Smiley_face")
//            model.scale *= SIMD3<Float>(repeating: 1.0)
           
            
            anchorEntity.addChild(model)
            
            av.session.add(anchor: arAnchor)
            av.scene.addAnchor(anchorEntity)
            
        }
        
       
    }
    
    
    
    
    
    
    
    
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        // every time the ARSession update its frame, this method gets invoked
        // Notice that because this app is using ARSession, so the frame can be directly captured from the ARSession using didUpdate since this class is the ARSession's delegate,
        // Getting frames from other processes like AVCaptureSession doesn't work because it will compete for the resource with the ARSession, causing unexpected behaviour
        
       
       
    }
    
    func remove_anchor(id: UUID) {

        DispatchQueue.main.async { [weak self] in

            guard let arView = self?.arView else {
                return
            }

            if let arAnchor = arView.session.currentFrame?
                .anchors
                .first(where: {
                    $0.name == id.uuidString
                }) {

                arView.session.remove(anchor: arAnchor)
            }

            if let anchorEntity = arView.scene.anchors
                .first(where: {
                    $0.name == id.uuidString
                }) {

                arView.scene.removeAnchor(anchorEntity)
            }
        }
    }
    
    func loadModel(model_name:String) -> ModelEntity {
        
        var modelEntity = ModelEntity()
        
        
        do {
            // Load the model from the bundle
            guard let modelURL = Bundle.main.url(forResource: model_name, withExtension: "usdz") else {
                fatalError("Failed to find model file.")
            }
            
            modelEntity = try ModelEntity.loadModel(contentsOf: modelURL)
            
            
            //modelEntity.position.y = 0.5 // Move the model 0.5 meters above the anchor
            
            
            
        } catch {
            print("Error loading model: \(error.localizedDescription)")
        }
        
        return modelEntity
            
        
    }
    
    func reset_anchor_capture() {
        visual_localisation_module.cleanup()
    }
    

    
    
    
    
}
