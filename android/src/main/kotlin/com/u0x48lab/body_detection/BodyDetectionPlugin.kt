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
    
    MLKitPoseDetector(
      stream = false,
      preferGPU = options?.get("preferGPU") as? Boolean ?: false,
      enableSegmentation = options?.get("enableSegmentation") as? Boolean ?: false,
      enableAccuratePoseDetection = options?.get("enableAccuratePoseDetection") as? Boolean ?: true
    ).process(
      image,
      OnSuccessListener { pose ->
        result.success(MLKitUtils.poseLandmarksToMap(pose))
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
      handleCameraFrame(imageProxy, rotationDegrees)
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
  private fun handleCameraFrame(imageProxy: ImageProxy, rotationDegrees: Int) {
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

      // --- ML Kit Pose Detection ---
      if (poseDetectionEnabled) {
        try {
          // Use bitmap approach for now to avoid ImageProxy closure issues
          val bitmap = BitmapUtils.getBitmap(imageProxy, true)
          if (bitmap != null) {
            val image = InputImage.fromBitmap(bitmap, 0)
            println("Created InputImage from Bitmap for pose detection")

            poseDetector?.let { detector ->
              val processed = detector.process(
                image,
                OnSuccessListener { pose ->
                  // Only send pose data if the pose is not null and has landmarks
                  if (pose != null && pose.allPoseLandmarks.isNotEmpty()) {
                    println("✅ POSE DETECTED with ${pose.allPoseLandmarks.size} landmarks")
                    eventSink?.success(mapOf(
                      "type" to "pose",
                      "pose" to MLKitUtils.poseLandmarksToMap(pose)
                    ))
                  } else {
                    println("⚠️ Pose detected but no landmarks")
                  }
                  // Clean up bitmap after successful processing
                  bitmap.recycle()
                },
                OnFailureListener { error ->
                  // Log pose detection errors for debugging
                  println("Pose detection error: ${error.localizedMessage}")
                  error.printStackTrace()
                  // Clean up bitmap after failed processing
                  bitmap.recycle()
                }
              )
              if (!processed) {
                println("Pose detector failed to process frame - detector busy")
                bitmap.recycle() // Clean up if processing failed
              }
            } ?: run {
              println("Pose detector is null")
              bitmap.recycle() // Clean up if no detector
            }
          } else {
            println("Failed to create bitmap for pose detection")
          }
        } catch (e: Exception) {
          println("Error in pose detection: ${e.localizedMessage}")
          e.printStackTrace()
        }
      }

      // Selfie segmentation has been removed as it's not used.
    } catch (e: Exception) {
      // Handle any errors gracefully
      e.printStackTrace()
    } finally {
      // Always close the imageProxy
      imageProxy.close()
    }
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
