package com.u0x48lab.body_detection

import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseLandmark

object MLKitUtils {
    fun poseLandmarksToMap(pose: Pose): Map<String, Any> {
        val landmarks = mutableListOf<Map<String, Any>>()
        
        pose.allPoseLandmarks.forEach { landmark ->
            val landmarkType = when (landmark.landmarkType) {
                PoseLandmark.NOSE -> "nose"
                PoseLandmark.LEFT_EYE_INNER -> "leftEyeInner"
                PoseLandmark.LEFT_EYE -> "leftEye"
                PoseLandmark.LEFT_EYE_OUTER -> "leftEyeOuter"
                PoseLandmark.RIGHT_EYE_INNER -> "rightEyeInner"
                PoseLandmark.RIGHT_EYE -> "rightEye"
                PoseLandmark.RIGHT_EYE_OUTER -> "rightEyeOuter"
                PoseLandmark.LEFT_EAR -> "leftEar"
                PoseLandmark.RIGHT_EAR -> "rightEar"
                PoseLandmark.LEFT_MOUTH -> "mouthLeft"
                PoseLandmark.RIGHT_MOUTH -> "mouthRight"
                PoseLandmark.LEFT_SHOULDER -> "leftShoulder"
                PoseLandmark.RIGHT_SHOULDER -> "rightShoulder"
                PoseLandmark.LEFT_ELBOW -> "leftElbow"
                PoseLandmark.RIGHT_ELBOW -> "rightElbow"
                PoseLandmark.LEFT_WRIST -> "leftWrist"
                PoseLandmark.RIGHT_WRIST -> "rightWrist"
                PoseLandmark.LEFT_PINKY -> "leftPinkyFinger"
                PoseLandmark.RIGHT_PINKY -> "rightPinkyFinger"
                PoseLandmark.LEFT_INDEX -> "leftIndexFinger"
                PoseLandmark.RIGHT_INDEX -> "rightIndexFinger"
                PoseLandmark.LEFT_THUMB -> "leftThumb"
                PoseLandmark.RIGHT_THUMB -> "rightThumb"
                PoseLandmark.LEFT_HIP -> "leftHip"
                PoseLandmark.RIGHT_HIP -> "rightHip"
                PoseLandmark.LEFT_KNEE -> "leftKnee"
                PoseLandmark.RIGHT_KNEE -> "rightKnee"
                PoseLandmark.LEFT_ANKLE -> "leftAnkle"
                PoseLandmark.RIGHT_ANKLE -> "rightAnkle"
                PoseLandmark.LEFT_HEEL -> "leftHeel"
                PoseLandmark.RIGHT_HEEL -> "rightHeel"
                PoseLandmark.LEFT_FOOT_INDEX -> "leftToe"
                PoseLandmark.RIGHT_FOOT_INDEX -> "rightToe"
                else -> return@forEach
            }

            landmarks.add(mapOf(
                "part" to landmarkType,
                "x" to landmark.position.x,
                "y" to landmark.position.y,
                "visibility" to landmark.inFrameLikelihood
            ))
        }

        return mapOf("landmarks" to landmarks)
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
