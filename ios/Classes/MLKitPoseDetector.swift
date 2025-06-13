import Foundation
import MLImage
import MLKitVision
import MLKitCommon
import MLKitPoseDetectionCommon
import MLKitPoseDetection
import MLKitPoseDetectionAccurate


class MLKitPoseDetector {
    private let poseDetector: PoseDetector
    // Removed isWorking flag - no longer needed with asynchronous API

    init(stream: Bool) {
        let options = AccuratePoseDetectorOptions()
        options.detectorMode = stream ? .stream : .singleImage
        self.poseDetector = PoseDetector.poseDetector(options: options)
    }

    // Existing method for UIImage (synchronous - for static image detection)
    func detectPose(image: UIImage?) -> Pose? {
        guard let image = image else { return nil }

        guard let inputImage = MLImage(image: image) else {
            print("Failed to create MLImage from UIImage.")
            return nil
        }
        inputImage.orientation = image.imageOrientation

        do {
            let poses = try poseDetector.results(in: inputImage)
            return poses.first
        } catch let error {
            print("Failed to detect poses from UIImage with error: \(error.localizedDescription).")
            return nil
        }
    }

    // Legacy synchronous method for CMSampleBuffer (kept for compatibility)
    func detectPose(sampleBuffer: CMSampleBuffer, imageOrientation: UIImage.Orientation) -> Pose? {
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation

        do {
            let poses = try poseDetector.results(in: visionImage)
            return poses.first
        } catch let error {
            print("Failed to detect poses from sample buffer with error: \(error.localizedDescription).")
            return nil
        }
    }

    // New asynchronous method for CMSampleBuffer - prevents blocking and eliminates need for isWorking flag
    func detectPoseAsync(sampleBuffer: CMSampleBuffer, imageOrientation: UIImage.Orientation, completion: @escaping (Pose?) -> Void) {
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation

        poseDetector.process(visionImage) { poses, error in
            if let error = error {
                print("Failed to detect poses from sample buffer with error: \(error.localizedDescription).")
                completion(nil)
                return
            }

            completion(poses?.first)
        }
    }
}
