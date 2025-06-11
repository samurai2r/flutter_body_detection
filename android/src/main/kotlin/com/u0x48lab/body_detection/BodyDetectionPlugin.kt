package com.u0x48lab.body_detection

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.annotation.NonNull
import androidx.camera.core.ImageProxy
import com.google.android.gms.tasks.OnFailureListener
import com.google.android.gms.tasks.OnSuccessListener
import com.google.mlkit.vision.common.InputImage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/** BodyDetectionPlugin */
class BodyDetectionPlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var context: Context
  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private var eventSink: EventChannel.EventSink? = null
  private var cameraSession: CameraSession? = null
  private var poseDetectionEnabled = false
  // private var bodyMaskDetectionEnabled = false // Body mask detection removed as it's not used
  private var poseDetector: MLKitPoseDetector? = null
  // private var selfieSegmenter: MLKitSelfieSegmenter? = null // Selfie segmenter removed for performance

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext

    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.0x48lab/body_detection")
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "com.0x48lab/body_detection/image_stream")
    eventChannel.setStreamHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
    when (call.method) {
      "detectImagePose" -> handleDetectImagePose(call, result)
      // "detectImageSegmentationMask" -> handleDetectImageSegmentationMask(call, result) // Removed for performance
      "enablePoseDetection" -> handleEnablePoseDetection(call, result)
      "disablePoseDetection" -> handleDisablePoseDetection(result)
      // "enableBodyMaskDetection" -> handleEnableBodyMaskDetection(result) // Removed for performance
      // "disableBodyMaskDetection" -> handleDisableBodyMaskDetection(result) // Removed for performance
      "startCameraStream" -> handleStartCameraStream(result)
      "stopCameraStream" -> handleStopCameraStream(result)
      else -> result.notImplemented()
    }
  }

  private fun handleDetectImagePose(call: MethodCall, result: MethodChannel.Result) {
    val imageData = call.argument<ByteArray>("pngImageBytes")
    val options = call.argument<Map<String, Any>>("options")

    if (imageData == null) {
      result.error("invalid_parameter", "PNG image bytes cannot be null", null)
      return
    }

    val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
    val image = InputImage.fromBitmap(bitmap, 0)

    // For static image detection, assume front camera (can be made configurable if needed)
    val isFrontCamera = options?.get("isFrontCamera") as? Boolean ?: true

    MLKitPoseDetector(
      stream = false,
      preferGPU = options?.get("preferGPU") as? Boolean ?: false,
      enableSegmentation = options?.get("enableSegmentation") as? Boolean ?: false,
      enableAccuratePoseDetection = options?.get("enableAccuratePoseDetection") as? Boolean ?: true
    ).process(
      image,
      OnSuccessListener { pose ->
        result.success(MLKitUtils.poseLandmarksToMap(pose, isFrontCamera))
      },
      OnFailureListener { e ->
        result.error("PoseDetectorError", e.localizedMessage, e.stackTrace)
      }
    )
  }

  // Selfie segmentation methods removed for performance optimization
  // Body mask detection methods are now effectively no-ops if called, consider removing from Flutter side.

  private fun handleEnablePoseDetection(call: MethodCall, result: MethodChannel.Result) {
    println("handleEnablePoseDetection called")
    val options = call.argument<Map<String, Any>>("options")
    poseDetector?.close()
    poseDetector = MLKitPoseDetector(
      stream = true,
      preferGPU = options?.get("preferGPU") as? Boolean ?: false,
      enableSegmentation = options?.get("enableSegmentation") as? Boolean ?: false,
      enableAccuratePoseDetection = options?.get("enableAccuratePoseDetection") as? Boolean ?: true
    )
    poseDetectionEnabled = true
    println("Pose detection enabled: $poseDetectionEnabled, detector created: ${poseDetector != null}")
    result.success(null)
  }

  private fun handleDisablePoseDetection(result: MethodChannel.Result) {
    poseDetectionEnabled = false
    poseDetector?.close()
    poseDetector = null
    result.success(null)
  }



  private fun handleStartCameraStream(result: MethodChannel.Result) {
    val session = CameraSession(context)
    session.start { imageProxy, rotationDegrees ->
      // Check if camera is front-facing
      val isFrontCamera = session.isFrontCamera()
      handleCameraFrame(imageProxy, rotationDegrees, isFrontCamera)
    }
    cameraSession = session
    result.success(true)
  }

  private fun handleStopCameraStream(result: MethodChannel.Result) {
    cameraSession?.stop()
    cameraSession = null
    result.success(true)
  }

  @SuppressLint("UnsafeExperimentalUsageError")
  private fun handleCameraFrame(imageProxy: ImageProxy, rotationDegrees: Int, isFrontCamera: Boolean = true) {
    var imageProxyClosed = false

    fun safeCloseImageProxy() {
      if (!imageProxyClosed) {
        imageProxy.close()
        imageProxyClosed = true
      }
    }

    try {
      // Debug logging
      println("handleCameraFrame called - poseDetectionEnabled: $poseDetectionEnabled, imageProxy.image: ${imageProxy.image != null}")

      // --- Preview Image for Flutter (only when eventSink is available) ---
      // This part is for sending a preview image to Flutter. It can be optimized further if needed,
      // but for now, we keep it to maintain existing functionality.
      // It's now separate from the ML Kit processing path.
      var previewBitmapForFlutter: Bitmap? = null
      if (eventSink != null) { // Only prepare bitmap if eventSink is available
        previewBitmapForFlutter = BitmapUtils.getBitmap(imageProxy, true)
      }

      if (previewBitmapForFlutter != null && eventSink != null) {
        val width = previewBitmapForFlutter.width
        val height = previewBitmapForFlutter.height
        val output = ByteArrayOutputStream()
        previewBitmapForFlutter.compress(Bitmap.CompressFormat.JPEG, 60, output) // Kept at 60% quality

        eventSink?.success(mapOf(
          "type" to "image",
          "image" to output.toByteArray(),
          "width" to width,
          "height" to height
        ))

        // Recycle preview bitmap after use
        previewBitmapForFlutter.recycle()
      }

      // --- ML Kit Pose Detection (Direct ImageProxy - Maximum Performance) ---
      if (poseDetectionEnabled && imageProxy.image != null) {
        try {
          // Use direct ImageProxy processing - much faster than bitmap conversion
          val image = InputImage.fromMediaImage(imageProxy.image!!, rotationDegrees)
          println("🚀 Created InputImage from MediaImage (direct processing)")

          poseDetector?.let { detector ->
            val processed = detector.process(
              image,
              OnSuccessListener { pose ->
                try {
                  // Only send pose data if the pose is not null and has landmarks
                  if (pose != null && pose.allPoseLandmarks.isNotEmpty()) {
                    println("✅ POSE DETECTED with ${pose.allPoseLandmarks.size} landmarks (direct processing)")
                    eventSink?.success(mapOf(
                      "type" to "pose",
                      "pose" to MLKitUtils.poseLandmarksToMap(pose, isFrontCamera)
                    ))
                  } else {
                    println("⚠️ Pose detected but no landmarks (direct processing)")
                  }
                } catch (e: Exception) {
                  println("Error processing pose result: ${e.localizedMessage}")
                  e.printStackTrace()
                } finally {
                  // Close ImageProxy after successful processing
                  safeCloseImageProxy()
                }
              },
              OnFailureListener { error ->
                try {
                  // Log pose detection errors for debugging
                  println("Pose detection error (direct processing): ${error.localizedMessage}")
                  error.printStackTrace()
                } finally {
                  // Close ImageProxy after failed processing
                  safeCloseImageProxy()
                }
              }
            )
            if (!processed) {
              println("Pose detector failed to process frame - detector busy")
              safeCloseImageProxy() // Close if processing failed to start
            }
          } ?: run {
            println("Pose detector is null")
            safeCloseImageProxy() // Close if no detector
          }
        } catch (e: Exception) {
          println("Error creating InputImage from MediaImage: ${e.localizedMessage}")
          e.printStackTrace()
          safeCloseImageProxy() // Close on error
        }
      } else {
        // No pose detection enabled or no image data, close immediately
        if (poseDetectionEnabled) {
          println("Pose detection enabled but imageProxy.image is null")
        }
        safeCloseImageProxy()
      }

      // Selfie segmentation has been removed as it's not used.
    } catch (e: Exception) {
      // Handle any errors gracefully
      println("Error in handleCameraFrame: ${e.localizedMessage}")
      e.printStackTrace()
      safeCloseImageProxy() // Ensure cleanup on any error
    }
    // Note: No finally block - ImageProxy closure is handled by ML Kit callbacks or error cases
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    poseDetector?.close()
    poseDetector = null
    // selfieSegmenter = null // Removed as it's no longer used
    cameraSession?.stop()
    cameraSession = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
}
