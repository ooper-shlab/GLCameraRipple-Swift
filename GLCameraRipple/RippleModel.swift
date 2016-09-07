//
//  RippleModel.swift
//  GLCameraRipple
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/9/5.
//
//
/*
     File: RippleModel.h
     File: RippleModel.m
 Abstract: Ripple model class that simulates the ripple effect.
  Version: 1.0

 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.

 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.

 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

 Copyright (C) 2013 Apple Inc. All Rights Reserved.

 */

import Foundation
import OpenGLES.ES2.gl
import CoreGraphics

class RippleModel: NSObject {
    
    private var screenWidth: Int
    private var screenHeight: Int
    private var poolWidth: Int
    private var poolHeight: Int
    private var touchRadius: Int
    
    private var meshFactor: Int
    
    private var texCoordFactorS: Float
    private var texCoordOffsetS: Float
    private var texCoordFactorT: Float
    private var texCoordOffsetT: Float
    
    // ripple coefficients
    private var rippleCoeff: UnsafeMutablePointer<Float>
    private var rippleCoeffCount: Int
    
    // ripple simulation buffers
    private var rippleSource: UnsafeMutablePointer<Float>
    private var rippleSourceCount: Int
    private var rippleDest: UnsafeMutablePointer<Float>
    private var rippleDestCount: Int
    
    // data passed to GL
    private var rippleVertices: UnsafeMutablePointer<GLfloat>
    private var rippleVerticesCount: Int
    private var rippleTexCoords: UnsafeMutablePointer<GLfloat>
    private var rippleTexCoordsCount: Int
    private var rippleIndicies: UnsafeMutablePointer<GLushort>
    private var rippleIndiciesCount: Int
    
    private func initRippleMap() {
        // +2 for padding the border
        rippleSource.initialize(to: 0, count: rippleSourceCount)
        rippleDest.initialize(to: 0, count: rippleDestCount)
    }
    
    private func initRippleCoeff() {
        for y in 0...2*touchRadius {
            for x in 0...2*touchRadius {
                //let distance = sqrt(Float((x-touchRadius)*(x-touchRadius)+(y-touchRadius)*(y-touchRadius)))
                let xDiff = (x-touchRadius)
                let yDiff = (y-touchRadius)
                let distance = sqrt(Float(xDiff*xDiff+yDiff*yDiff))
                
                if distance <= Float(touchRadius) {
                    let factor = (distance/Float(touchRadius))
                    
                    // goes from -512 -> 0
                    rippleCoeff[y*(touchRadius*2+1)+x] = -(cos(factor*Float(M_PI))+1.0) * 256.0
                } else {
                    rippleCoeff[y*(touchRadius*2+1)+x] = 0.0
                }
            }
        }
    }
    
    private func initMesh() {
        for i in 0..<poolHeight {
            for j in 0..<poolWidth {
                rippleVertices[(i*poolWidth+j)*2+0] = -1.0 + Float(j)*(2.0/Float(poolWidth-1))
                rippleVertices[(i*poolWidth+j)*2+1] = 1.0 - Float(i)*(2.0/Float(poolHeight-1))
                
                rippleTexCoords[(i*poolWidth+j)*2+0] = Float(i)/Float(poolHeight-1) * texCoordFactorS + texCoordOffsetS
                rippleTexCoords[(i*poolWidth+j)*2+1] = (1.0 - Float(j)/Float(poolWidth-1)) * texCoordFactorT + texCoordFactorT
            }
        }
        
        var index = 0
        for i in 0..<poolHeight-1 {
            for j in 0..<poolWidth {
                if i%2 == 0 {
                    // emit extra index to create degenerate triangle
                    if j == 0 {
                        rippleIndicies[index] = GLushort(i*poolWidth+j)
                        index += 1
                    }
                    
                    rippleIndicies[index] = GLushort(i*poolWidth+j)
                    index += 1
                    rippleIndicies[index] = GLushort((i+1)*poolWidth+j)
                    index += 1
                    
                    // emit extra index to create degenerate triangle
                    if j == (poolWidth-1) {
                        rippleIndicies[index] = GLushort((i+1)*poolWidth+j)
                        index += 1
                    }
                } else {
                    // emit extra index to create degenerate triangle
                    if j == 0 {
                        rippleIndicies[index] = GLushort((i+1)*poolWidth+j)
                        index += 1
                    }
                    
                    rippleIndicies[index] = GLushort((i+1)*poolWidth+j)
                    index += 1
                    rippleIndicies[index] = GLushort(i*poolWidth+j)
                    index += 1
                    
                    // emit extra index to create degenerate triangle
                    if j == (poolWidth-1) {
                        rippleIndicies[index] = GLushort(i*poolWidth+j)
                        index += 1
                    }
                }
            }
        }
    }
    
    var vertices: UnsafePointer<GLfloat> {
        return UnsafePointer(rippleVertices)
    }
    
    var texCoords:  UnsafePointer<GLfloat> {
        return UnsafePointer(rippleTexCoords)
    }
    
    var indices: UnsafePointer<GLushort> {
        return UnsafePointer(rippleIndicies)
    }
    
    var vertexSize: Int {
        return poolWidth*poolHeight*2*MemoryLayout<GLfloat>.size
    }
    
    var indexSize: Int {
        return indexCount*MemoryLayout<GLushort>.size
    }
    
    var indexCount: Int {
        return (poolHeight-1)*(poolWidth*2+2)
    }
    
    private func freeBuffers() {
        rippleCoeff.deallocate(capacity: rippleCoeffCount)
        
        rippleSource.deallocate(capacity: rippleSourceCount)
        rippleDest.deallocate(capacity: rippleDestCount)
        
        rippleVertices.deallocate(capacity: rippleVerticesCount)
        rippleTexCoords.deallocate(capacity: rippleTexCoordsCount)
        rippleIndicies.deallocate(capacity: rippleIndiciesCount)
    }
    
    init(screenWidth width: Int, screenHeight height: Int,
         meshFactor factor: Int, touchRadius radius: Int,
         textureWidth texWidth: Int, textureHeight texHeight: Int)
    {
        
        screenWidth = width
        screenHeight = height
        meshFactor = factor
        let poolWidth = width/factor //### to use within phase1 init
        self.poolWidth = poolWidth
        let poolHeight = height/factor //### to use within phase1 init
        self.poolHeight = poolHeight
        touchRadius = radius
        
        if Float(height)/Float(width) < Float(texWidth)/Float(texHeight) {
            texCoordFactorS = Float(texHeight*screenHeight)/Float(screenWidth*texWidth)
            texCoordOffsetS = (1.0 - texCoordFactorS)/2.0
            
            texCoordFactorT = 1.0
            texCoordOffsetT = 0.0
        } else {
            texCoordFactorS = 1.0
            texCoordOffsetS = 0.0
            
            texCoordFactorT = Float(screenWidth*texWidth)/Float(texHeight*screenHeight)
            texCoordOffsetT = (1.0 - texCoordFactorT)/2.0
        }
        
        rippleCoeffCount = (radius*2+1)*(radius*2+1)
        rippleCoeff = .allocate(capacity: rippleCoeffCount)
        
        // +2 for padding the border
        rippleSourceCount = (poolWidth+2)*(poolHeight+2)
        rippleSource = .allocate(capacity: rippleSourceCount)
        rippleDestCount = (poolWidth+2)*(poolHeight+2)
        rippleDest = .allocate(capacity: rippleDestCount)
        
        rippleVerticesCount = poolWidth*poolHeight*2
        rippleVertices = .allocate(capacity: rippleVerticesCount)
        rippleTexCoordsCount = poolWidth*poolHeight*2
        rippleTexCoords = .allocate(capacity: rippleTexCoordsCount)
        rippleIndiciesCount = (poolHeight-1)*(poolWidth*2+2)
        rippleIndicies = .allocate(capacity: rippleIndiciesCount)
        
        super.init()
        
        self.initRippleMap()
        
        self.initRippleCoeff()
        
        self.initMesh()
        
    }
    
    func runSimulation() {
        //let queue = DispatchQueue.global(qos: .default) //###Why we cannot designate `queue` in `DispatchQueue.concurrentPerform`?
        
        // first pass for simulation buffers...
        DispatchQueue.concurrentPerform(iterations: poolHeight) {y in
            for x in 0..<poolWidth {
                // * - denotes current pixel
                //
                //       a
                //     c * d
                //       b
                
                // +1 to both x/y values because the border is padded
                let a = rippleSource[(y)*(poolWidth+2) + x+1]
                let b = rippleSource[(y+2)*(poolWidth+2) + x+1]
                let c = rippleSource[(y+1)*(poolWidth+2) + x]
                let d = rippleSource[(y+1)*(poolWidth+2) + x+2]
                
                var result = (a + b + c + d)/2.0 - rippleDest[(y+1)*(poolWidth+2) + x+1]
                
                result -= result/32.0
                
                rippleDest[(y+1)*(poolWidth+2) + x+1] = result
            }
        }
        
        // second pass for modifying texture coord
        DispatchQueue.concurrentPerform(iterations: poolHeight) {y in
            for x in 0..<poolWidth {
                // * - denotes current pixel
                //
                //       a
                //     c * d
                //       b
                
                // +1 to both x/y values because the border is padded
                let a = rippleDest[(y)*(poolWidth+2) + x+1]
                let b = rippleDest[(y+2)*(poolWidth+2) + x+1]
                let c = rippleDest[(y+1)*(poolWidth+2) + x]
                let d = rippleDest[(y+1)*(poolWidth+2) + x+2]
                
                var s_offset = ((b - a) / 2048.0)
                var t_offset = ((c - d) / 2048.0)
                
                // clamp
                s_offset = (s_offset < -0.5) ? -0.5 : s_offset
                t_offset = (t_offset < -0.5) ? -0.5 : t_offset
                s_offset = (s_offset > 0.5) ? 0.5 : s_offset
                t_offset = (t_offset > 0.5) ? 0.5 : t_offset
                
                let s_tc = Float(y)/Float(poolHeight-1) * texCoordFactorS + texCoordOffsetS
                let t_tc = (1.0 - Float(x)/Float(poolWidth-1)) * texCoordFactorT + texCoordOffsetT
                
                rippleTexCoords[(y*poolWidth+x)*2+0] = s_tc + s_offset
                rippleTexCoords[(y*poolWidth+x)*2+1] = t_tc + t_offset
            }
        }
        
        (rippleDest, rippleSource) = (rippleSource, rippleDest)
    }
    
    func initiateRippleAtLocation(_ location: CGPoint) {
        let xIndex = Int((location.x / CGFloat(screenWidth)) * CGFloat(poolWidth))
        let yIndex = Int((location.y / CGFloat(screenHeight)) * CGFloat(poolHeight))
        
        for y in yIndex-touchRadius...yIndex+touchRadius {
            for x in xIndex-touchRadius...xIndex+touchRadius {
                if x>=0 && x<poolWidth &&
                    y>=0 && y<poolHeight
                {
                    // +1 to both x/y values because the border is padded
                    rippleSource[(poolWidth+2)*(y+1)+x+1] += rippleCoeff[(y-(yIndex-touchRadius))*(touchRadius*2+1)+x-(xIndex-touchRadius)]
                }
            }
        }
    }
    
    deinit {
        self.freeBuffers()
    }
    
}
