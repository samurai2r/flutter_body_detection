package com.u0x48lab.body_detection

import com.google.android.gms.tasks.OnFailureListener
import com.google.android.gms.tasks.OnSuccessListener
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions

class MLKitPoseDetector(
    private val stream: Boolean,
    private val preferGPU: Boolean = false,
    private val enableSegmentation: Boolean = false,
    private val enableAccuratePoseDetection: Boolean = true
) {
    private val detector: PoseDetector
    private var task: Task<Pose>? = null

    init {
        val mode = if (stream) 
            AccuratePoseDetectorOptions.STREAM_MODE 
        else 
            AccuratePoseDetectorOptions.SINGLE_IMAGE_MODE

        val options = AccuratePoseDetectorOptions.Builder()
            .setDetectorMode(mode)
            .build()

        detector = PoseDetection.getClient(options)
    }

    fun process(
        image: InputImage,
        success: OnSuccessListener<Pose>,
        error: OnFailureListener
    ): Boolean {
        if (task != null) {
            error.onFailure(IllegalStateException("Previous detection task is still in progress"))
            return false
        }

        try {
            task = detector.process(image)
                .addOnSuccessListener { pose ->
                    try {
                        success.onSuccess(pose)
                    } catch (e: Exception) {
                        error.onFailure(e)
                    } finally {
                        task = null
                    }
                }
                .addOnFailureListener { e ->
                    error.onFailure(e)
                    task = null
                }

            return true
        } catch (e: Exception) {
            error.onFailure(e)
            task = null
            return false
        }
    }

    fun close() {
        try {
            detector.close()
        } catch (e: Exception) {
            // Log but don't throw
            e.printStackTrace()
        } finally {
            task = null
        }
    }
}