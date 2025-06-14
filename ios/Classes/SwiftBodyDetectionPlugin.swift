import Flutter
import UIKit
import Metal
import VideoToolbox

public class SwiftBodyDetectionPlugin: NSObject, FlutterPlugin {
    private let serialQueue = DispatchQueue(label: "swiftbodydetectionplugin.serial.queue")
    private var eventSink: FlutterEventSink?
    private var cameraSession: CameraSession?
    private var poseDetectionEnabled = false
    private var bodyMaskDetectionEnabled = false
    private let poseDetector = MLKitPoseDetector(stream: true)
    // private let selfieSegmenter = MLKitSelfieSegmenter() // Selfie segmenter removed as it's not used

    // Optimized Core Image context with Metal backend and dedicated serial queue
    private static let ciContext = CIContext(
        mtlDevice: MTLCreateSystemDefaultDevice()!,
        options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .cacheIntermediates: false  // Prevents hidden retain cycles and GPU texture leaks
        ]
    )
    private static let ciQueue = DispatchQueue(label: "ci.render.serial")  // Dedicated CI queue
    private static let poseDetectionQueue = DispatchQueue(label: "pose.detection.queue")  // Dedicated pose detection queue

    // Frame counter for preview throttling (optional optimization)
    private var frameCounter: Int = 0

    // Dynamic throttling based on device capabilities
    private lazy var previewThrottleFactor: Int = {
        return Self.getOptimalThrottleFactor()
    }()

    private static func getOptimalThrottleFactor() -> Int {
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion

        // Get device performance tier
        let performanceTier = getDevicePerformanceTier()

        switch performanceTier {
        case .high:
            return 2  // 15fps preview - smooth experience on powerful devices
        case .medium:
            return 3  // 10fps preview - balanced performance
        case .low:
            return 4  // 7.5fps preview - conservative for older devices
        }
    }

    private enum DevicePerformanceTier {
        case high, medium, low
    }

    private static func getDevicePerformanceTier() -> DevicePerformanceTier {
        // Use processor info to determine device capability
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }

        guard let model = modelCode else { return .medium }

        // High-performance devices (A15 Bionic and newer)
        if model.contains("iPhone14,") ||  // iPhone 13 series
           model.contains("iPhone15,") ||  // iPhone 14 series
           model.contains("iPhone16,") ||  // iPhone 15 series
           model.contains("iPhone17,") ||  // iPhone 16 series
           model.contains("iPad14,") ||    // iPad Pro M2
           model.contains("iPad16,") {     // iPad Pro M4
            return .high
        }

        // Medium-performance devices (A12-A14 Bionic)
        if model.contains("iPhone11,") ||  // iPhone XS/XR
           model.contains("iPhone12,") ||  // iPhone 11 series
           model.contains("iPhone13,") ||  // iPhone 12 series
           model.contains("iPad11,") ||    // iPad Pro 2018-2020
           model.contains("iPad13,") {     // iPad Pro M1
            return .medium
        }

        // Low-performance devices (A11 and older, or unknown)
        return .low
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftBodyDetectionPlugin()

        let channel = FlutterMethodChannel(name: "com.0x48lab/body_detection", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(name: "com.0x48lab/body_detection/image_stream", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)

        // Register for memory pressure and background notifications
        instance.setupNotificationObservers()

        // Log the selected throttling factor for debugging
        print("Body Detection: Using preview throttle factor \(instance.previewThrottleFactor) for device performance optimization")
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleMemoryPressure() {
        SwiftBodyDetectionPlugin.ciQueue.async {
            SwiftBodyDetectionPlugin.ciContext.clearCaches()
        }
    }

    @objc private func handleAppDidEnterBackground() {
        SwiftBodyDetectionPlugin.ciQueue.async {
            SwiftBodyDetectionPlugin.ciContext.clearCaches()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Note: this method is invoked on the UI thread.
        switch (call.method) {
        
        // Handle detectPose calls.
        case "detectImagePose":
            do {
                // Assume arguments are of dictionary type.
                guard let arguments = call.arguments as? [String : Any] else {
                    throw BodyDetectionPluginError.badArgument("Expected dictionary type.")
                }
                guard let pngBytes = arguments["pngImageBytes"] as? FlutterStandardTypedData else {
                    throw BodyDetectionPluginError.badArgument("pngImageBytes")
                }
                serialQueue.async {
                    do {
                        guard let uiImage = UIImage(data: pngBytes.data) else {
                            throw BodyDetectionPluginError.custom("ConversionError", message: "UIImage could not be created with provided data.")
                        }
                        
                        let detector = MLKitPoseDetector(stream: false)
                        let pose = detector.detectPose(image: uiImage)

                        // For static image detection, assume front camera (can be made configurable if needed)
                        let resultValue = pose?.toMap(isFrontCamera: true)
                        
                        DispatchQueue.main.async {
                            result(resultValue)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(error.toFlutterError());
                        }
                    }
                }
            } catch {
                result(error.toFlutterError());
            }
            return
            
        // Handle detectSegmentationMask calls.
        case "detectImageSegmentationMask":
            do {
                // Assume arguments are of dictionary type.
                guard let arguments = call.arguments as? [String : Any] else {
                    throw BodyDetectionPluginError.badArgument("Expected dictionary type.")
                }
                guard let pngBytes = arguments["pngImageBytes"] as? FlutterStandardTypedData else {
                    throw BodyDetectionPluginError.badArgument("pngImageBytes")
                }
                serialQueue.async {
                    do {
                        guard let uiImage = UIImage(data: pngBytes.data) else {
                            throw BodyDetectionPluginError.custom("ConversionError", message: "UIImage could not be created with provided data.")
                        }
                        
                        let segmenter = MLKitSelfieSegmenter()
                        guard let mask = segmenter.detectSegmentationMask(image: uiImage) else {
                            throw BodyDetectionPluginError.custom("SegmentationFailed", message: "Segmentation mask could not be detected.")
                        }
                        
                        let resultValue = mask.toMap()
                        
                        DispatchQueue.main.async {
                            result(resultValue)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(error.toFlutterError());
                        }
                    }
                }
            } catch {
                result(error.toFlutterError());
            }
            return
            
        // Handle enablePoseDetection calls.
        case "enablePoseDetection":
            self.poseDetectionEnabled = true
            result(nil)
            return
            
        // Handle disablePoseDetection calls.
        case "disablePoseDetection":
            self.poseDetectionEnabled = false
            result(nil)
            return
            
        // Handle enableSelfieSegmentation calls.
        case "enableBodyMaskDetection":
            self.bodyMaskDetectionEnabled = true
            result(nil)
            return
            
        // Handle disableSelfieSegmentation calls.
        case "disableBodyMaskDetection":
            self.bodyMaskDetectionEnabled = false
            result(nil)
            return
            
        // Body mask detection methods are now effectively no-ops if called, consider removing from Flutter side.

        // Handle startCameraStreamPoseDetection calls.
        case "startCameraStream":
            guard self.cameraSession == nil else {
                print("Camera session already active! Call stopCameraStream first and try again.")
                return
            }
            let session = CameraSession()
            session.start(closure: self.handleCameraFrame)
            self.cameraSession = session
            result(true)
            return
            
        // Handle stopCameraStreamPoseDetection calls.
        case "stopCameraStream":
            guard let session = self.cameraSession else {
                print("Camera session is not active!")
                return
            }
            session.stop()
            self.cameraSession = nil
            result(true)
            return
            
        // Method not implemented.
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleCameraFrame(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            self.eventSink?(BodyDetectionPluginError.custom("CameraFrame", message: "Failed to get image buffer from sample buffer.").toFlutterError())
            return
        }

        frameCounter += 1

        // --- Asynchronous Pose Detection (always execute - no frame drops) ---
        if self.poseDetectionEnabled {
            SwiftBodyDetectionPlugin.poseDetectionQueue.async { [weak self] in
                self?.performPoseDetection(sampleBuffer: sampleBuffer, orientation: orientation)
            }
        }

        // --- Preview Generation (throttled and on dedicated CI queue) ---
        // Generate preview based on device capabilities for optimal performance
        if self.eventSink != nil && frameCounter.isMultiple(of: previewThrottleFactor) {
            // Capture the pixel buffer in the closure to ensure it stays alive
            SwiftBodyDetectionPlugin.ciQueue.async { [weak self, imageBuffer] in
                autoreleasepool {
                    self?.generatePreviewImage(imageBuffer: imageBuffer, orientation: orientation)
                }
            }
        }

        // Periodic cache clearing to prevent memory buildup
        if frameCounter.isMultiple(of: 300) { // Every ~10 seconds at 30fps
            SwiftBodyDetectionPlugin.ciQueue.async {
                SwiftBodyDetectionPlugin.ciContext.clearCaches()
            }
        }
    }

    private func performPoseDetection(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) {
        // Use asynchronous ML Kit API to prevent blocking
        self.poseDetector.detectPoseAsync(sampleBuffer: sampleBuffer, imageOrientation: orientation) { [weak self] pose in
            guard let self = self, let pose = pose, !pose.landmarks.isEmpty else { return }

            // Check if camera is front-facing
            let isFrontCamera = self.cameraSession?.isFrontCamera() ?? true

            DispatchQueue.main.async {
                self.eventSink?([
                    "type": "pose",
                    "pose": pose.toMap(isFrontCamera: isFrontCamera) as Any
                ])
            }
        }
    }

    private func generatePreviewImage(imageBuffer: CVPixelBuffer, orientation: UIImage.Orientation) {
        // Try Core Image first, fallback to VideoToolbox if CI fails
        if let previewImage = generatePreviewWithCoreImage(imageBuffer: imageBuffer, orientation: orientation) {
            sendPreviewToFlutter(previewImage)
        } else if let previewImage = generatePreviewWithVideoToolbox(imageBuffer: imageBuffer, orientation: orientation) {
            sendPreviewToFlutter(previewImage)
        }
    }

    private func generatePreviewWithCoreImage(imageBuffer: CVPixelBuffer, orientation: UIImage.Orientation) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        guard let cgImage = SwiftBodyDetectionPlugin.ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }

    private func generatePreviewWithVideoToolbox(imageBuffer: CVPixelBuffer, orientation: UIImage.Orientation) -> UIImage? {
        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)

        guard status == noErr, let validCGImage = cgImage else {
            return nil
        }

        return UIImage(cgImage: validCGImage, scale: 1.0, orientation: orientation)
    }

    private func sendPreviewToFlutter(_ previewImage: UIImage) {
        guard let data = previewImage.jpegData(compressionQuality: 0.6),
              let cgImg = previewImage.cgImage else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.eventSink?([
                "type": "image",
                "image": data,
                "width": cgImg.width,
                "height": cgImg.height
            ])
        }
    }
}

// MARK: FlutterStreamHandler

extension SwiftBodyDetectionPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        
        return nil
    }
}

enum BodyDetectionPluginError: Error {
    case badArgument(_ name: String)
    case custom(_ code: String, message: String?)
}

