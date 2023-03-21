//
//  SceneKitParticlesView.swift
//  macai
//
//  Created by Renat Notfullin on 19.03.2023.
//

import SwiftUI
import SceneKit

struct SceneKitParticlesView: NSViewRepresentable {
    func makeNSView(context: Context) -> SCNView {
        
        let scnView = SCNView()
        scnView.scene = SCNScene()
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.backgroundColor = NSColor.clear
        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 50)
        scnView.scene?.rootNode.addChildNode(cameraNode)
        
        let colors: [NSColor] = [NSColor(red: 1, green: 230/255, blue: 140/255, alpha: 1), NSColor(red: 1, green: 190/255, blue: 95/255, alpha: 0.7), NSColor(red: 200/255, green: 223/255, blue: 255/255, alpha: 0.8)]
        
        let particleNode = SCNNode()
        for color in colors {
            let particleSystem = createWarmColorParticleSystem(color: color)
            particleNode.addParticleSystem(particleSystem)
        }
        
        scnView.scene?.rootNode.addChildNode(particleNode)
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
    }
    
    func createWarmColorParticleSystem(color: NSColor) -> SCNParticleSystem {
        let particleSystem = SCNParticleSystem()

        particleSystem.particleSize = CGFloat.random(in: 0.05...0.2)
        particleSystem.particleImage = NSImage(named: "Particle")
        particleSystem.particleColor = color
        particleSystem.particleColorVariation = SCNVector4(0.1, 0.1, 0.1, 0.5)
        particleSystem.emitterShape = SCNPlane()
        particleSystem.birthRate = 100
        particleSystem.particleLifeSpan = 10
        particleSystem.particleVelocity = 20
        particleSystem.spreadingAngle = 180
        particleSystem.speedFactor = 0.1
        particleSystem.blendMode = .additive
        return particleSystem
    }

//    func createWarmColorParticleSystem(color: NSColor) -> SCNParticleSystem {
//        let particleSystem = SCNParticleSystem()
//
//        particleSystem.particleColor = color
//        particleSystem.birthRate = 1000
//        particleSystem.particleLifeSpan = 15
//        particleSystem.loops = true
//        particleSystem.emissionDuration = .greatestFiniteMagnitude
//        particleSystem.particleSize = 15
//        particleSystem.particleSizeVariation = 10
//        particleSystem.emitterShape = SCNSphere(radius: 15)
//        particleSystem.birthLocation = .surface
//        particleSystem.birthDirection = .surfaceNormal
//        particleSystem.spreadingAngle = 180
//        particleSystem.particleVelocity = 10
//        particleSystem.particleVelocityVariation = 5
//        particleSystem.speedFactor = 0.5
//        particleSystem.emissionDurationVariation = 5
//        particleSystem.particleBounce = 0.2
//        particleSystem.particleBounceVariation = 0.1
//        particleSystem.particleFriction = 0.1
//        particleSystem.particleFrictionVariation = 0.05
//        particleSystem.blendMode = .additive
//
//        return particleSystem
//    }

}
