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

    // Circuit breaker for Core Image - disable if too many failures
    private var coreImageFailureCount: Int = 0
    private var coreImageDisabled: Bool = false
    private let maxCoreImageFailures: Int = 5

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

        // Monitor thermal state changes for additional memory management
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
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

    @objc private func handleThermalStateChange() {
        let thermalState = ProcessInfo.processInfo.thermalState
        print("Body Detection: Thermal state changed to \(thermalState)")

        // Aggressive cache clearing on thermal pressure
        if thermalState == .serious || thermalState == .critical {
            SwiftBodyDetectionPlugin.ciQueue.async {
                SwiftBodyDetectionPlugin.ciContext.clearCaches()
                // Force immediate cleanup
                autoreleasepool { }
            }
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

        // More aggressive cache clearing to prevent CI crashes
        let cacheInterval = getCacheClearingInterval()
        if frameCounter.isMultiple(of: cacheInterval) {
            SwiftBodyDetectionPlugin.ciQueue.async {
                SwiftBodyDetectionPlugin.ciContext.clearCaches()
                // Force garbage collection of any lingering CI objects
                autoreleasepool { }
            }
        }
    }

    private func getCacheClearingInterval() -> Int {
        // Adjust cache clearing frequency based on memory pressure
        let thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .critical:
            return 30   // Every second at 30fps - very aggressive
        case .serious:
            return 90   // Every 3 seconds - aggressive
        case .fair:
            return 150  // Every 5 seconds - moderate
        case .nominal:
            return 300  // Every 10 seconds - normal
        @unknown default:
            return 300
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
        // Check circuit breaker and memory pressure
        let memoryPressure = ProcessInfo.processInfo.thermalState
        let shouldUseCoreImage = !coreImageDisabled &&
                                memoryPressure != .critical &&
                                memoryPressure != .serious

        var previewImage: UIImage?

        if shouldUseCoreImage {
            // Try Core Image with circuit breaker pattern
            do {
                previewImage = try generatePreviewWithCoreImageSafe(imageBuffer: imageBuffer, orientation: orientation)
                // Reset failure count on success
                if previewImage != nil {
                    coreImageFailureCount = 0
                }
            } catch {
                print("Core Image preview generation failed: \(error.localizedDescription)")
                coreImageFailureCount += 1

                // Disable Core Image if too many failures
                if coreImageFailureCount >= maxCoreImageFailures {
                    coreImageDisabled = true
                    print("Body Detection: Core Image disabled due to repeated failures. Using VideoToolbox only.")
                }
                previewImage = nil
            }
        }

        // Fallback to VideoToolbox if CI failed, disabled, or memory pressure is high
        if previewImage == nil {
            previewImage = generatePreviewWithVideoToolbox(imageBuffer: imageBuffer, orientation: orientation)
        }

        if let image = previewImage {
            sendPreviewToFlutter(image)
        }
    }

    private func generatePreviewWithCoreImageSafe(imageBuffer: CVPixelBuffer, orientation: UIImage.Orientation) throws -> UIImage? {
        // Wrap Core Image operations in error handling
        return try autoreleasepool {
            return generatePreviewWithCoreImage(imageBuffer: imageBuffer, orientation: orientation)
        }
    }

    private func generatePreviewWithCoreImage(imageBuffer: CVPixelBuffer, orientation: UIImage.Orientation) -> UIImage? {
        // Additional safety checks to prevent CI crashes
        guard CVPixelBufferGetWidth(imageBuffer) > 0 && CVPixelBufferGetHeight(imageBuffer) > 0 else {
            return nil
        }

        // Create CIImage with explicit options to prevent texture issues
        let ciImage = CIImage(cvPixelBuffer: imageBuffer, options: [
            .colorSpace: NSNull(),  // Prevent color space conversion issues
            .applyOrientationProperty: false  // Handle orientation manually
        ])

        // Validate image extent before processing
        let extent = ciImage.extent
        guard extent.width > 0 && extent.height > 0 && !extent.isInfinite else {
            return nil
        }

        // Use a smaller render region to reduce GPU memory pressure
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / extent.width, maxDimension / extent.height, 1.0)
        let renderRect = CGRect(x: 0, y: 0, width: extent.width * scale, height: extent.height * scale)

        guard let cgImage = SwiftBodyDetectionPlugin.ciContext.createCGImage(ciImage, from: renderRect) else {
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

