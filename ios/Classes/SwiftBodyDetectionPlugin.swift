import Flutter
import UIKit

public class SwiftBodyDetectionPlugin: NSObject, FlutterPlugin {
    private let serialQueue = DispatchQueue(label: "swiftbodydetectionplugin.serial.queue")
    private var eventSink: FlutterEventSink?
    private var cameraSession: CameraSession?
    private var poseDetectionEnabled = false
    private var bodyMaskDetectionEnabled = false
    private let poseDetector = MLKitPoseDetector(stream: true)
    // private let selfieSegmenter = MLKitSelfieSegmenter() // Selfie segmenter removed as it's not used

    // Shared Core Image context to prevent crashes from multiple instances
    private static let sharedCIContext = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull()
    ])
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftBodyDetectionPlugin()
        
        let channel = FlutterMethodChannel(name: "com.0x48lab/body_detection", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let eventChannel = FlutterEventChannel(name: "com.0x48lab/body_detection/image_stream", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
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
                        
                        let resultValue = pose?.toMap()
                        
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
        do {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw BodyDetectionPluginError.custom("CameraFrame", message: "Failed to get image buffer from sample buffer.")
            }

            // --- Image for Event Sink (Preview to Flutter) ---
            // This part is for sending a preview image to Flutter. It can be optimized further if needed,
            // but for now, we keep it to maintain existing functionality.
            // It's now separate from the ML Kit processing path.
            var previewImageForFlutter: UIImage? = nil
            if self.eventSink != nil { // Only prepare image if eventSink is available
                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                if let cgImage = SwiftBodyDetectionPlugin.sharedCIContext.createCGImage(ciImage, from: ciImage.extent) {
                    let rotatedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
                    // Removed expensive redraw. Using UIImage from CGImage directly.
                    previewImageForFlutter = rotatedImage
                }
            }

            if let imageToSend = previewImageForFlutter, let eventSink = self.eventSink {
                if let data = imageToSend.jpegData(compressionQuality: 0.6), // Lowered quality for less data
                   let cgImg = imageToSend.cgImage {
                    eventSink([
                        "type": "image",
                        "image": data,
                        "width": cgImg.width,
                        "height": cgImg.height
                    ])
                }
            }
            
            // --- ML Kit Pose Detection (using CMSampleBuffer directly) ---
            if self.poseDetectionEnabled {
                // Use the new detector method with CMSampleBuffer and orientation
                if let pose = self.poseDetector.detectPose(sampleBuffer: sampleBuffer, imageOrientation: orientation), !pose.landmarks.isEmpty {
                    self.eventSink?([
                        "type": "pose",
                        "pose": pose.toMap() as Any
                    ])
                }
                // Otherwise, do not send a pose event for this frame
            }

            // Selfie segmentation has been removed as it's not used.
        } catch {
            self.eventSink?(error.toFlutterError())
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

