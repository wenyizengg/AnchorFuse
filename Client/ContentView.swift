//
// Copyright (C) 2026 Wenyi Chen

//  ContentView.swift
//  AR_demo2
//
//  Created by Wenyi on 09/03/2025.
//

import SwiftUI
import RealityKit
import ARKit
import simd

private enum AnchorSaveUIState: Equatable {
    case idle
    case saving
    case saved
    case failed
}


enum AnchorPlacementMethod: Equatable {
    case gpsEstimate
    case visualLocalisation

    var label: String {
        switch self {
        case .gpsEstimate:
            return "GPS Estimate"
        case .visualLocalisation:
            return "Visual Localisation"
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = ViewModel()
    @State private var showCameraUI = false
    @State private var photosTaken = 0
    @State private var saveState: AnchorSaveUIState = .idle
    @State private var promptCaptureFailure = false
    @State private var promptNoAnchorToSave = false
    private var showSaved: Bool {
        saveState == .saved
    }

    private var promptSaveFailure: Bool {
        saveState == .failed
    }
    
    var body: some View {
        ZStack {
           
            ARViewContainer(vm: vm).edgesIgnoringSafeArea(.all)
            
            VStack {
                if let placementMethod = vm.anchorPlacementMethod {
                    HStack {
                        Text("Placement: \(placementMethod.label)")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                Spacer()
                
                if showSaved {
                    prompt(text: "Anchor saved.", color: .green)
                }
                
                if promptCaptureFailure {
                    prompt(text: "Capture failed: insufficient visual/depth data.", color: .red)
                }
                
                if promptSaveFailure {
                    prompt(
                        text: "Failed to save anchor.",
                        color: .red
                    )
                }
                
                if promptNoAnchorToSave {
                    prompt(text: "No anchor to be saved!", color: .red)
                }
                
                if !showCameraUI {
                        Button(
                            saveState == .saving
                                ? "Saving..."
                                : "Save anchor"
                        ) {
                            
                            guard let check_save_anchor_condition = vm.check_save_anchor_condition else {return}
                            
                            if !check_save_anchor_condition() {
                                
                                promptNoAnchorToSave = true
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    promptNoAnchorToSave = false
                                }
                                
                                
                                return
                            }
                            
                            else {
                                vm.reset_anchor_capture?()
                                photosTaken = 0
                                showCameraUI = true
                            }
                            
                        }
                        .padding()
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom, 20)
//                        .transition(.opacity)  // animation
                        .animation(.easeInOut, value: showCameraUI)
                        .disabled(saveState == .saving)
                }
                    
                
                // show camera panel
                if showCameraUI {
                    CameraControlView(
                        
                        photosTaken: $photosTaken,
                        showCameraUI: $showCameraUI,
                        
                        
                        takePhotoAction: {
                            
                            guard let capture = vm.capture, let save = vm.send_anchor else {
                                return
                            }
                            
                            let captureResult = capture()
                            
                            if !captureResult {
                                promptCaptureFailure = true
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    promptCaptureFailure = false
                                }
                                
                            }
                            
                            else {
                                
                                if photosTaken == 4 {
                                    
                                    showCameraUI = false
                                    photosTaken = 0
                                    
                                    saveState = .saving

                                    save { success in
                                        let resultState:
                                            AnchorSaveUIState =
                                                success
                                                ? .saved
                                                : .failed

                                        saveState = resultState

                                        DispatchQueue.main.asyncAfter(
                                            deadline: .now() + 1.5
                                        ) {
                                            // Do not clear a newer state.
                                            if saveState == resultState {
                                                saveState = .idle
                                            }
                                        }
                                    }


                                } else {
                                    photosTaken += 1
                                }
                                
                            }
                            
                        },
                        
                        cancelAction: {
                            vm.reset_anchor_capture?()
                        },
                        
                        
         
                        
                    )
                    //.transition(.move(edge: .bottom))
                    .animation(.easeInOut, value: showCameraUI)
                }
                
                
            }
        }
    }
    
}


struct ARViewContainer: UIViewRepresentable {
    
    let vm: ViewModel
    
    func makeCoordinator() -> Coordinator {
            return Coordinator()
    }
    
    func makeUIView(context: Context) -> ARView {
        
        let arView = ARView(frame: .zero)
        vm.arView = arView
        
     
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        
        config.environmentTexturing = .none // Disable environment mapping
        config.sceneReconstruction = []

        // MARK: The visual-localisation pipeline requires LiDAR support
        if #available(iOS 14.0, *) {
            if ARWorldTrackingConfiguration.supportsFrameSemantics(
                [.sceneDepth, .smoothedSceneDepth]
            ) {
                config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(
                .sceneDepth
            ) {
                config.frameSemantics = [.sceneDepth]
            } else {
                print(
                    "LiDAR scene depth is unavailable on this device; " +
                    "metric keyframe capture is disabled."
                )
            }
        } else {
            print(
                "LiDAR scene depth requires iOS 14 or later; " +
                "metric keyframe capture is disabled."
            )
        }
        
        config.worldAlignment = .gravity
        // Pitch and roll of the origin are always align with the gravity
        
        
        arView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapping)))
        
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        context.coordinator.onPlacementMethodChanged = { [weak vm] method in
            vm?.anchorPlacementMethod = method
        }
        
        vm.capture = context.coordinator.capture
        vm.check_save_anchor_condition = context.coordinator.check_anchor_saving_condition
        vm.send_anchor = context.coordinator.save_anchor
        
        vm.reset_anchor_capture =
            context.coordinator.reset_anchor_capture
        
        arView.session.run(config)
        
 
        
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}


struct CameraControlView: View {
    
    
    @Binding var photosTaken: Int
    @Binding var showCameraUI: Bool
    let takePhotoAction: () -> Void
    let cancelAction: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Keyframe captured:  \(photosTaken)/5")
                .font(.headline)
            
            Button(action: takePhotoAction) {
                Image(systemName: "camera")
                    .font(.largeTitle)
                    .padding()
                    .background(Circle().fill(Color.black))
                    .foregroundColor(.white)
            }
            
            Button("Cancel") {
                cancelAction()
                showCameraUI = false
                photosTaken = 0
            }
            .foregroundColor(.red)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
        .padding(.bottom, 40)
    }
}

struct prompt: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .padding()
            .foregroundColor(color)
            .cornerRadius(10)
            .transition(.opacity)
    }
}


class ViewModel: ObservableObject {

    @Published var anchorPlacementMethod: AnchorPlacementMethod?
    
    weak var arView: ARView?
    let frameProcessor = frame_processor_wrapper()

    var capture: (()->Bool)?
    var check_save_anchor_condition:(()->Bool)?

    
    var send_anchor:
        ((@escaping (Bool) -> Void) -> Void)?

    var reset_anchor_capture: (() -> Void)?

}


