package com.u0x48lab.body_detection

import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseLandmark

object MLKitUtils {
    fun poseLandmarksToMap(pose: Pose): Map<String, Any> {
        val landmarks = mutableMapOf<String, Any>()
        
        // Map MLKit landmark types to original types
        val landmarkMappings = mapOf(
            PoseLandmark.LEFT_ANKLE to "leftAnkle",
            PoseLandmark.LEFT_EAR to "leftEar",
            PoseLandmark.LEFT_ELBOW to "leftElbow",
            PoseLandmark.LEFT_EYE to "leftEye",
            PoseLandmark.LEFT_EYE_INNER to "leftEyeInner",
            PoseLandmark.LEFT_EYE_OUTER to "leftEyeOuter",
            PoseLandmark.LEFT_HEEL to "leftHeel",
            PoseLandmark.LEFT_HIP to "leftHip",
            PoseLandmark.LEFT_INDEX to "leftIndexFinger",
            PoseLandmark.LEFT_KNEE to "leftKnee",
            PoseLandmark.LEFT_PINKY to "leftPinkyFinger",
            PoseLandmark.LEFT_SHOULDER to "leftShoulder",
            PoseLandmark.LEFT_THUMB to "leftThumb",
            PoseLandmark.LEFT_FOOT_INDEX to "leftToe",
            PoseLandmark.LEFT_WRIST to "leftWrist",
            PoseLandmark.LEFT_MOUTH to "mouthLeft",
            PoseLandmark.RIGHT_MOUTH to "mouthRight",
            PoseLandmark.NOSE to "nose",
            PoseLandmark.RIGHT_ANKLE to "rightAnkle",
            PoseLandmark.RIGHT_EAR to "rightEar",
            PoseLandmark.RIGHT_ELBOW to "rightElbow",
            PoseLandmark.RIGHT_EYE to "rightEye",
            PoseLandmark.RIGHT_EYE_INNER to "rightEyeInner",
            PoseLandmark.RIGHT_EYE_OUTER to "rightEyeOuter",
            PoseLandmark.RIGHT_HEEL to "rightHeel",
            PoseLandmark.RIGHT_HIP to "rightHip",
            PoseLandmark.RIGHT_INDEX to "rightIndexFinger",
            PoseLandmark.RIGHT_KNEE to "rightKnee",
            PoseLandmark.RIGHT_PINKY to "rightPinkyFinger",
            PoseLandmark.RIGHT_SHOULDER to "rightShoulder",
            PoseLandmark.RIGHT_THUMB to "rightThumb",
            PoseLandmark.RIGHT_FOOT_INDEX to "rightToe",
            PoseLandmark.RIGHT_WRIST to "rightWrist"
        )

        pose.allPoseLandmarks.forEach { landmark ->
            val landmarkType = landmarkMappings[landmark.landmarkType] ?: return@forEach
            landmarks[landmarkType] = mapOf(
                "x" to landmark.position3D.x,
                "y" to landmark.position3D.y,
                "z" to landmark.position3D.z,
                "likelihood" to landmark.inFrameLikelihood,
                "type" to landmark.landmarkType
            )
        }

        return landmarks
    }

    fun getPoseLandmarkPosition(landmark: PoseLandmark): Map<String, Any> {
        return mapOf(
            "x" to landmark.position3D.x,
            "y" to landmark.position3D.y,
            "z" to landmark.position3D.z,
            "likelihood" to landmark.inFrameLikelihood
        )
    }
}
