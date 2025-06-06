import Foundation
import MLImage
import MLKitVision
import MLKitCommon
import MLKitPoseDetectionCommon
import MLKitPoseDetection
import MLKitPoseDetectionAccurate


class MLKitPoseDetector {
    private let poseDetector: PoseDetector
    private var isWorking = false

    init(stream: Bool) {
        let options = AccuratePoseDetectorOptions()
        options.detectorMode = stream ? .stream : .singleImage
        self.poseDetector = PoseDetector.poseDetector(options: options)
    }

    // Existing method for UIImage
    func detectPose(image: UIImage?) -> Pose? {
        guard let image = image else { return nil }

        guard let inputImage = MLImage(image: image) else {
            print("Failed to create MLImage from UIImage.")
            return nil
        }
        inputImage.orientation = image.imageOrientation

        guard !self.isWorking else { return nil }
        self.isWorking = true
        defer {
            self.isWorking = false
        }

        do {
            let poses = try poseDetector.results(in: inputImage)
            return poses.first
        } catch let error {
            print("Failed to detect poses from UIImage with error: \(error.localizedDescription).")
            return nil
        }
    }

    // New method for CMSampleBuffer
    func detectPose(sampleBuffer: CMSampleBuffer, imageOrientation: UIImage.Orientation) -> Pose? {
        guard !self.isWorking else {
            // print("Pose detector is already working on a frame.") // Optional: reduce log noise if too frequent
            return nil
        }
        self.isWorking = true
        defer {
            self.isWorking = false
        }

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation // Use the pre-calculated orientation from CameraSession + UIUtilities

        do {
            let poses = try poseDetector.results(in: visionImage)
            return poses.first
        } catch let error {
            print("Failed to detect poses from sample buffer with error: \(error.localizedDescription).")
            return nil
        }
    }
}
