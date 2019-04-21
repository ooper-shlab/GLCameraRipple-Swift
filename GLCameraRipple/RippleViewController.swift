//
//  RippleViewController.swift
//  GLCameraRipple
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/9/5.
//
//
/*
     File: RippleViewController.h
     File: RippleViewController.m
 Abstract: View controller that handles camera, drawing, and touch events.
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

import UIKit
import GLKit
import AVFoundation

import CoreVideo.CVOpenGLESTextureCache

// Uniform index.
private let UNIFORM_Y = 0
private let UNIFORM_UV = 1
private let NUM_UNIFORMS = 2
private var uniforms: [GLint] = [0, 0]

// Attribute index.
private let ATTRIB_VERTEX = 0
private let ATTRIB_TEXCOORD = 1
private let NUM_ATTRIBUTES = 2

class RippleViewController: GLKViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _program: GLuint = 0
    
    private var _positionVBO: GLuint = 0
    private var _texcoordVBO: GLuint = 0
    private var _indexVBO: GLuint = 0
    
    private var _screenWidth: CGFloat = 0.0
    private var _screenHeight: CGFloat = 0.0
    private var _textureWidth: CGFloat = 0.0
    private var _textureHeight: CGFloat = 0.0
    private var _meshFactor: Int = 0
    
    private var _context: EAGLContext!
    private var _ripple: RippleModel?
    
    private var _lumaTexture: CVOpenGLESTexture?
    private var _chromaTexture: CVOpenGLESTexture?
    
    private var _sessionPreset: String = convertFromAVCaptureSessionPreset(AVCaptureSession.Preset.vga640x480)
    
    private var _session: AVCaptureSession?
    private var _videoTextureCache: CVOpenGLESTextureCache?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        _context = EAGLContext(api: .openGLES2)
        
        if _context == nil {
            NSLog("Failed to create ES context")
        }
        
        let view = self.view as! GLKView
        view.context = _context
        self.preferredFramesPerSecond = 60
        
        _screenWidth = UIScreen.main.bounds.size.width
        _screenHeight = UIScreen.main.bounds.size.height
        view.contentScaleFactor = UIScreen.main.scale
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            // meshFactor controls the ending ripple mesh size.
            // For example mesh width = screenWidth / meshFactor.
            // It's chosen based on both screen resolution and device size.
            _meshFactor = 8
            
            // Choosing bigger preset for bigger screen.
            _sessionPreset = convertFromAVCaptureSessionPreset(AVCaptureSession.Preset.hd1280x720)
        } else {
            _meshFactor = 4
            _sessionPreset = convertFromAVCaptureSessionPreset(AVCaptureSession.Preset.vga640x480)
        }
        
        self.setupGL()
        
        self.setupAVCapture()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.tearDownAVCapture()
        
        self.tearDownGL()
        
        if EAGLContext.current() === _context {
            EAGLContext.setCurrent(nil)
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc. that aren't in use.
    }
    
    // Camera image orientation on screen is fixed
    // with respect to the physical camera orientation.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    override var shouldAutorotate: Bool {
        return true
    }
    
    private func cleanUpTextures() {
        if _lumaTexture != nil {
            _lumaTexture = nil
        }
        
        if _chromaTexture != nil {
            _chromaTexture = nil
        }
        
        // Periodic texture cache flush every frame
        CVOpenGLESTextureCacheFlush(_videoTextureCache!, 0)
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            fatalError("pixelBuffer cannot be retrieved")
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard let videoTextureCache = _videoTextureCache else {
            NSLog("No video texture cache")
            return
        }
        
        if _ripple == nil ||
            CGFloat(width) != _textureWidth ||
            CGFloat(height) != _textureHeight
        {
            _textureWidth = CGFloat(width)
            _textureHeight = CGFloat(height)
            
            _ripple = RippleModel(screenWidth: Int(_screenWidth),
                                  screenHeight: Int(_screenHeight),
                                  meshFactor: _meshFactor,
                                  touchRadius: 5,
                                  textureWidth: Int(_textureWidth),
                                  textureHeight: Int(_textureHeight))
            
            self.setupBuffers()
        }
        
        self.cleanUpTextures()
        
        // CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture
        // optimally from CVImageBufferRef.
        
        // Y-plane
        glActiveTexture(GLenum(GL_TEXTURE0))
        var err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               videoTextureCache,
                                                               pixelBuffer,
                                                               nil,
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_RED_EXT,
                                                               GLsizei(_textureWidth),
                                                               GLsizei(_textureHeight),
                                                               GLenum(GL_RED_EXT),
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               0,
                                                               &_lumaTexture)
        if err != 0 {
            NSLog("Error at CVOpenGLESTextureCacheCreateTextureFromImage \(err)");
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture!), CVOpenGLESTextureGetName(_lumaTexture!))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        
        // UV-plane
        glActiveTexture(GLenum(GL_TEXTURE1))
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           videoTextureCache,
                                                           pixelBuffer,
                                                           nil,
                                                           GLenum(GL_TEXTURE_2D),
                                                           GL_RG_EXT,
                                                           GLsizei(_textureWidth/2),
                                                           GLsizei(_textureHeight/2),
                                                           GLenum(GL_RG_EXT),
                                                           GLenum(GL_UNSIGNED_BYTE),
                                                           1,
                                                           &_chromaTexture)
        if err != 0 {
            NSLog("Error at CVOpenGLESTextureCacheCreateTextureFromImage \(err)")
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture!), CVOpenGLESTextureGetName(_chromaTexture!))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
    }
    
    private func setupAVCapture() {
        //-- Create CVOpenGLESTextureCacheRef for optimal CVImageBufferRef to GLES texture conversion.
        let err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, _context, nil, &_videoTextureCache)
        guard err == 0 else {
            NSLog("Error at CVOpenGLESTextureCacheCreate \(err)")
            return
        }
        
        //-- Setup Capture Session.
        _session = AVCaptureSession()
        _session?.beginConfiguration()
        
        //-- Set preset session size.
        _session?.canSetSessionPreset(AVCaptureSession.Preset(rawValue: _sessionPreset))
        
        //-- Creata a video device and input from that Device.  Add the input to the capture session.
        guard let videoDevice = AVCaptureDevice.default(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video))) else {
            fatalError()
        }
        
        //-- Add the device to the session.
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            fatalError(error.localizedDescription)
        }
        
        _session?.addInput(input)
        
        //-- Create the output for the capture session.
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.alwaysDiscardsLateVideoFrames = true // Probably want to set this to NO when recording
        
        //-- Set to YUV420.
        dataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as NSString: // Necessary for manual preview
                NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)] as [String : Any]
        
        // Set dispatch to be on the main thread so OpenGL can do things with the data
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        
        _session?.addOutput(dataOutput)
        _session?.commitConfiguration()
        
        _session?.startRunning()
    }
    
    private func tearDownAVCapture() {
        self.cleanUpTextures()
        
        _videoTextureCache = nil
    }
    
    func setupBuffers() {
        glGenBuffers(1, &_indexVBO)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), _indexVBO)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), _ripple!.indexSize, _ripple!.indices, GLenum(GL_STATIC_DRAW))
        
        glGenBuffers(1, &_positionVBO)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), _positionVBO)
        glBufferData(GLenum(GL_ARRAY_BUFFER), _ripple!.vertexSize, _ripple!.vertices, GLenum(GL_STATIC_DRAW))
        
        glEnableVertexAttribArray(GLuint(ATTRIB_VERTEX))
        glVertexAttribPointer(GLuint(ATTRIB_VERTEX), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(2*MemoryLayout<GLfloat>.size), nil)
        
        glGenBuffers(1, &_texcoordVBO)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), _texcoordVBO)
        glBufferData(GLenum(GL_ARRAY_BUFFER), _ripple!.vertexSize, _ripple!.texCoords, GLenum(GL_DYNAMIC_DRAW))
        
        glEnableVertexAttribArray(GLuint(ATTRIB_TEXCOORD))
        glVertexAttribPointer(GLuint(ATTRIB_TEXCOORD), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(2*MemoryLayout<GLfloat>.size), nil)
    }
    
    private func setupGL() {
        EAGLContext.setCurrent(_context)
        
        self.loadShaders()
        
        glUseProgram(_program)
        
        glUniform1i(uniforms[UNIFORM_Y], 0)
        glUniform1i(uniforms[UNIFORM_UV], 1)
    }
    
    private func tearDownGL() {
        EAGLContext.setCurrent(_context)
        
        glDeleteBuffers(1, &_positionVBO)
        glDeleteBuffers(1, &_texcoordVBO)
        glDeleteBuffers(1, &_indexVBO)
        
        if _program != 0 {
            glDeleteProgram(_program)
            _program = 0
        }
    }
    
    //MARK: - GLKView and GLKViewController delegate methods
    
    @objc func update() {
        if let ripple = _ripple {
            ripple.runSimulation()
            
            // no need to rebind GL_ARRAY_BUFFER to _texcoordVBO since it should be still be bound from setupBuffers
            glBufferData(GLenum(GL_ARRAY_BUFFER), ripple.vertexSize, ripple.texCoords, GLenum(GL_DYNAMIC_DRAW))
        }
    }
    
    override func glkView(_ view: GLKView, drawIn rect: CGRect) {
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        if let ripple = _ripple {
            glDrawElements(GLenum(GL_TRIANGLE_STRIP), GLsizei(ripple.indexCount), GLenum(GL_UNSIGNED_SHORT), nil)
        }
    }
    
    //MARK: - Touch handling methods
    
    private func myTouch(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: touch.view)
            _ripple?.initiateRippleAtLocation(location)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.myTouch(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.myTouch(touches, with: event)
    }
    
    //MARK: - OpenGL ES 2 shader compilation
    
    @discardableResult
    func loadShaders() -> Bool {
        var vertShader: GLuint = 0, fragShader: GLuint = 0
        
        // Create shader program.
        _program = glCreateProgram()
        
        // Create and compile vertex shader.
        let vertShaderURL = Bundle.main.url(forResource: "Shader", withExtension: "vsh")!
        guard compileShader(&vertShader, type: GLenum(GL_VERTEX_SHADER), url: vertShaderURL) else {
            NSLog("Failed to compile vertex shader")
            return false
        }
        
        // Create and compile fragment shader.
        let fragShaderURL = Bundle.main.url(forResource: "Shader", withExtension: "fsh")!
        guard compileShader(&fragShader, type: GLenum(GL_FRAGMENT_SHADER), url: fragShaderURL) else {
            NSLog("Failed to compile fragment shader")
            return false
        }
        
        // Attach vertex shader to program.
        glAttachShader(_program, vertShader)
        
        // Attach fragment shader to program.
        glAttachShader(_program, fragShader)
        
        // Bind attribute locations.
        // This needs to be done prior to linking.
        glBindAttribLocation(_program, GLuint(ATTRIB_VERTEX), "position")
        glBindAttribLocation(_program, GLuint(ATTRIB_TEXCOORD), "texCoord")
        
        // Link program.
        guard linkProgram(_program) else {
            NSLog("Failed to link program: \(_program)")
            
            if vertShader != 0 {
                glDeleteShader(vertShader)
                vertShader = 0
            }
            if fragShader != 0 {
                glDeleteShader(fragShader)
                fragShader = 0
            }
            if _program != 0 {
                glDeleteProgram(_program)
                _program = 0
            }
            
            return false
        }
        
        // Get uniform locations.
        uniforms[UNIFORM_Y] = glGetUniformLocation(_program, "SamplerY")
        uniforms[UNIFORM_UV] = glGetUniformLocation(_program, "SamplerUV")
        
        // Release vertex and fragment shaders.
        if vertShader != 0 {
            glDetachShader(_program, vertShader)
            glDeleteShader(vertShader)
        }
        if fragShader != 0 {
            glDetachShader(_program, fragShader)
            glDeleteShader(fragShader)
        }
        
        return true
    }
    
    func compileShader(_ shader: UnsafeMutablePointer<GLuint>, type: GLenum, url: URL) -> Bool {
        var status: GLint = 0
        
        guard var source = try? Data(contentsOf: url) else {
            NSLog("Failed to load vertex shader")
            return false
        }
        source.append(0)
        
        shader.pointee = glCreateShader(type)
        source.withUnsafeBytes{bytes in
            var bytePtr = bytes.bindMemory(to: GLchar.self).baseAddress
            glShaderSource(shader.pointee, 1, &bytePtr, nil)
            glCompileShader(shader.pointee)
        }
        
        //#if DEBUG
        var logLength: GLint = 0
        glGetShaderiv(shader.pointee, GLenum(GL_INFO_LOG_LENGTH), &logLength)
        if logLength > 0 {
            var log: [GLchar] = Array(repeating: 0, count: Int(logLength))
            glGetShaderInfoLog(shader.pointee, logLength, &logLength, &log)
            NSLog("Shader compile log:\n\(String(cString: log))")
        }
        //#endif
        
        glGetShaderiv(shader.pointee, GLenum(GL_COMPILE_STATUS), &status)
        guard status != 0 else {
            glDeleteShader(shader.pointee)
            return false
        }
        
        return true
    }
    
    func linkProgram(_ prog: GLuint) -> Bool {
        var status: GLint = 0
        glLinkProgram(prog)
        
        #if DEBUG
            var logLength: GLint = 0
            glGetProgramiv(prog, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if logLength > 0 {
                var log: [GLchar] = Array(repeating: 0, count: Int(logLength))
                glGetProgramInfoLog(prog, logLength, &logLength, &log)
                NSLog("Program link log:\n\(String(cString: log))")
            }
        #endif
        
        glGetProgramiv(prog, GLenum(GL_LINK_STATUS), &status)
        if status == 0 {
            return false
        }
        
        return true
    }
    
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVCaptureSessionPreset(_ input: AVCaptureSession.Preset) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVMediaType(_ input: AVMediaType) -> String {
	return input.rawValue
}
