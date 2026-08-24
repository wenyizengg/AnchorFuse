//
// Copyright (C) 2026 Wenyi Chen
//  Anchor_saving_service.swift
//  AR_demo2
//
//  Created by Wenyi on 17/03/2025.
//

import Foundation
import Network
import ARKit
import RealityKit

final class Anchor_saving_service {

    weak var coordinator: Coordinator?

    private let connection: NWConnection
    private let connectionQueue = DispatchQueue(
        label: "AnchorSavingService.connection"
    )

    init(
        host: String,
        port: UInt16,
        coordinator: Coordinator
    ) {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            fatalError("Invalid anchor-saving port: \(port)")
        }

        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: networkPort,
            using: .tcp
        )
        self.coordinator = coordinator

        start()
    }

    private func start() {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Anchor saving service connected to server.")

            case .failed(let error):
                print("Failed connecting to server: \(error)")

            case .waiting(let error):
                print("Waiting to connect: \(error)")

            case .setup:
                print("Setting up anchor-saving connection.")

            case .cancelled:
                print("Anchor-saving connection cancelled.")

            default:
                break
            }
        }

        connection.start(queue: connectionQueue)
    }

    func save_anchor(
        anchor_info: Anchor_information,
        completion: @escaping (Bool) -> Void
    ) {
        guard let coordinator else {
            completeOnMain(false, completion: completion)
            return
        }

        let bytes = anchor_info.binarise()

        guard !bytes.isEmpty else {
            print("Anchor serialization failed; nothing was sent.")
            completeOnMain(false, completion: completion)
            return
        }

        connection.send(
            content: bytes,
            completion: .contentProcessed { [weak self] error in
                guard let self else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }

                if let error {
                    print(
                        "Error sending anchor data to the server: \(error)"
                    )
                    self.completeOnMain(
                        false,
                        completion: completion
                    )
                    return
                }

                // The server sends exactly one byte after PostgreSQL transaction finishes:
                //   1 = committed successfully
                //   0 = insertion failed
                self.receiveSaveAcknowledgement(
                    anchorInfo: anchor_info,
                    coordinator: coordinator,
                    completion: completion
                )
            }
        )
    }

    private func receiveSaveAcknowledgement(
        anchorInfo: Anchor_information,
        coordinator: Coordinator,
        completion: @escaping (Bool) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 1
        ) { [weak self] content, _, _, error in
            guard let self else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            if let error {
                print(
                    "Failed receiving save acknowledgement: \(error)"
                )
                self.completeOnMain(
                    false,
                    completion: completion
                )
                return
            }

            guard let content,
                  content.count == 1 else {
                print("Invalid save acknowledgement size.")
                self.completeOnMain(
                    false,
                    completion: completion
                )
                return
            }

            let saved = content[content.startIndex] == 1

            guard saved else {
                print("The server failed to save the anchor.")
                self.completeOnMain(
                    false,
                    completion: completion
                )
                return
            }

            print("Anchor was committed to the database.")

            coordinator.nearby_anchors.append(anchorInfo)
            anchorInfo.status.set(2)

            self.completeOnMain(
                true,
                completion: completion
            )
        }
    }

    private func completeOnMain(
        _ success: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            completion(success)
        }
    }
}
