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
  private var bodyMaskDetectionEnabled = false
  private var poseDetector: MLKitPoseDetector? = null
  private var selfieSegmenter: MLKitSelfieSegmenter? = null

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
      "detectImageSegmentationMask" -> handleDetectImageSegmentationMask(call, result)
      "enablePoseDetection" -> handleEnablePoseDetection(call, result)
      "disablePoseDetection" -> handleDisablePoseDetection(result)
      "enableBodyMaskDetection" -> handleEnableBodyMaskDetection(result)
      "disableBodyMaskDetection" -> handleDisableBodyMaskDetection(result)
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

  private fun handleDetectImageSegmentationMask(call: MethodCall, result: MethodChannel.Result) {
    val imageData = call.argument<ByteArray>("pngImageBytes")
    if (imageData == null) {
      result.error("invalid_parameter", "PNG image bytes cannot be null", null)
      return
    }

    val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
    val image = InputImage.fromBitmap(bitmap, 0)
    
    MLKitSelfieSegmenter().process(
      image,
      OnSuccessListener { mask ->
        result.success(mask.toMap())
      },
      OnFailureListener { e ->
        result.error("SelfieSegmenterError", e.localizedMessage, e.stackTrace)
      }
    )
  }

  private fun handleEnablePoseDetection(call: MethodCall, result: MethodChannel.Result) {
    val options = call.argument<Map<String, Any>>("options")
    poseDetector?.close()
    poseDetector = MLKitPoseDetector(
      stream = true,
      preferGPU = options?.get("preferGPU") as? Boolean ?: false,
      enableSegmentation = options?.get("enableSegmentation") as? Boolean ?: false,
      enableAccuratePoseDetection = options?.get("enableAccuratePoseDetection") as? Boolean ?: true
    )
    poseDetectionEnabled = true
    result.success(null)
  }

  private fun handleDisablePoseDetection(result: MethodChannel.Result) {
    poseDetectionEnabled = false
    poseDetector?.close()
    poseDetector = null
    result.success(null)
  }

  private fun handleEnableBodyMaskDetection(result: MethodChannel.Result) {
    bodyMaskDetectionEnabled = true
    selfieSegmenter = MLKitSelfieSegmenter()
    result.success(null)
  }

  private fun handleDisableBodyMaskDetection(result: MethodChannel.Result) {
    bodyMaskDetectionEnabled = false
    selfieSegmenter = null
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
    val bitmap = BitmapUtils.getBitmap(imageProxy, true)
    val width = bitmap?.width ?: 0
    val height = bitmap?.height ?: 0
    val output = ByteArrayOutputStream()
    bitmap?.compress(Bitmap.CompressFormat.JPEG, 60, output)

    imageProxy.close()

    eventSink?.success(mapOf(
      "type" to "image",
      "image" to output.toByteArray(),
      "width" to width,
      "height" to height
    ))

    if ((poseDetectionEnabled || bodyMaskDetectionEnabled) && bitmap != null) {
      val image = InputImage.fromBitmap(bitmap, 0)
      var count = 2

      fun imageRefDown() {
        count -= 1
        if (count == 0) {
          bitmap.recycle()
        }
      }

      if (poseDetectionEnabled) {
        poseDetector?.let { detector ->
          val processed = detector.process(
            image,
            OnSuccessListener { pose ->
              // Only send pose data if the pose is not null and has landmarks
              if (pose != null && pose.allPoseLandmarks.isNotEmpty()) {
                eventSink?.success(mapOf(
                  "type" to "pose",
                  "pose" to MLKitUtils.poseLandmarksToMap(pose)
                ))
              }
              imageRefDown()
            },
            OnFailureListener { _ ->
              // Do not send null pose on failure, just skip the event for this frame
              imageRefDown()
            }
          )
          if (!processed) imageRefDown()
        } ?: imageRefDown()
      } else {
        imageRefDown()
      }

      if (bodyMaskDetectionEnabled) {
        selfieSegmenter?.let { segmenter ->
          val processed = segmenter.process(
            image,
            OnSuccessListener { mask ->
              eventSink?.success(mapOf(
                "type" to "mask",
                "mask" to mask.toMap()
              ))
              imageRefDown()
            },
            OnFailureListener { _ ->
              eventSink?.success(mapOf(
                "type" to "mask",
                "mask" to null
              ))
              imageRefDown()
            }
          )
          if (!processed) imageRefDown()
        } ?: imageRefDown()
      } else {
        imageRefDown()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    poseDetector?.close()
    poseDetector = null
    selfieSegmenter = null
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
