# Core Image CI::complete_intermediate Crash Fixes Implementation

## Overview
This document outlines the implementation of fixes for sporadic `CI::complete_intermediate` crashes in the Flutter body detection plugin. The fixes follow Apple's recommended best practices for Core Image usage in real-time camera applications.

## Key Changes Made

### 1. Dedicated Core Image Infrastructure
- **Metal-backed CIContext**: Created optimized context with `.cacheIntermediates: false` to prevent GPU texture leaks
- **Dedicated Serial Queue**: All Core Image operations now run on `ciQueue` to eliminate race conditions
- **Pixel Buffer Lifecycle Management**: Swift ARC capture pattern ensures pixel buffer stays alive during CI operations

### 2. Asynchronous ML Kit Processing
- **New Async API**: Switched from synchronous `results(in:)` to asynchronous `process(_:completion:)`
- **Removed Blocking**: Eliminated `isWorking` flag that was dropping frames
- **Dedicated Queue**: Pose detection runs on separate `poseDetectionQueue`

### 3. Optimized Preview Generation
- **Frame Throttling**: Preview generated every 3rd frame (configurable)
- **Separate Processing**: Preview and pose detection are completely decoupled
- **VideoToolbox Fallback**: Alternative preview generation if Core Image fails

### 4. Memory Management
- **Automatic Cache Clearing**: Periodic cleanup every 300 frames (~10 seconds)
- **Memory Pressure Handling**: Responds to system memory warnings
- **Background State Management**: Clears caches when app enters background

## File Changes

### SwiftBodyDetectionPlugin.swift
- Added Metal and VideoToolbox imports
- Created dedicated queues for CI and pose detection
- Implemented asynchronous frame processing with Swift ARC pixel buffer management
- Added memory pressure observers
- Implemented fallback preview generation methods

### MLKitPoseDetector.swift
- Added asynchronous `detectPoseAsync` method
- Removed `isWorking` flag and blocking behavior
- Kept synchronous methods for compatibility

## Technical Notes

### Swift ARC Memory Management
Instead of manual `CVPixelBufferRetain/Release`, we use Swift's ARC by capturing the `imageBuffer` in the async closure:

```swift
SwiftBodyDetectionPlugin.ciQueue.async { [weak self, imageBuffer] in
    // imageBuffer is automatically retained by ARC until this closure completes
    autoreleasepool {
        self?.generatePreviewImage(imageBuffer: imageBuffer, orientation: orientation)
    }
}
```

This approach:
- Ensures pixel buffer stays alive during CI operations
- Is compatible with modern Swift ARC
- Eliminates manual memory management errors
- Provides the same safety as manual retain/release

## Performance Benefits

1. **Zero Frame Drops**: Pose detection never blocks camera capture
2. **Reduced CI Workload**: Preview throttling cuts Core Image work by ~66%
3. **Better Memory Usage**: Automatic cache management prevents buildup
4. **Crash Elimination**: Single-threaded CI access prevents race conditions

## Testing Recommendations

### 1. Stress Testing
```bash
# Run app for extended periods (30+ minutes)
# Monitor for CI::complete_intermediate crashes
# Check memory usage over time
```

### 2. Memory Pressure Testing
```bash
# Simulate memory pressure while running detection
# Verify cache clearing works correctly
# Test background/foreground transitions
```

### 3. Performance Validation
```bash
# Measure pose detection latency
# Verify no frame drops in pose detection
# Check preview frame rate is acceptable
```

## Configuration Options

### Frame Throttling
```swift
// In handleCameraFrame, change the throttling factor:
if self.eventSink != nil && frameCounter.isMultiple(of: 3) {
    // Change '3' to adjust preview frequency
    // 1 = every frame, 2 = every other frame, etc.
}
```

### Cache Clearing Frequency
```swift
// In handleCameraFrame, adjust cache clearing:
if frameCounter.isMultiple(of: 300) {
    // Change '300' to adjust frequency
    // 300 frames ≈ 10 seconds at 30fps
}
```

### Fallback to VideoToolbox Only
If Core Image still causes issues, you can disable it entirely by modifying `generatePreviewImage`:

```swift
private func generatePreviewImage(imageBuffer: CVPixelBuffer, orientation: UIImage.Orientation) {
    // Skip Core Image, use VideoToolbox only
    if let previewImage = generatePreviewWithVideoToolbox(imageBuffer: imageBuffer, orientation: orientation) {
        sendPreviewToFlutter(previewImage)
    }
}
```

## Monitoring

### Key Metrics to Watch
- Crash reports for CI::complete_intermediate
- Memory usage growth over time
- Pose detection latency
- Preview frame rate
- CPU usage

### Debug Logging
Add these logs to monitor performance:

```swift
// In generatePreviewImage
print("Preview generation method: \(usedCoreImage ? "CoreImage" : "VideoToolbox")")

// In performPoseDetection
let startTime = CFAbsoluteTimeGetCurrent()
// ... detection code ...
print("Pose detection took: \(CFAbsoluteTimeGetCurrent() - startTime)s")
```

## Rollback Plan

If issues persist, you can selectively disable optimizations:

1. **Disable frame throttling**: Set throttling factor to 1
2. **Disable VideoToolbox fallback**: Remove fallback method
3. **Revert to synchronous ML Kit**: Use original `detectPose` method
4. **Disable cache clearing**: Comment out periodic cache clearing

The changes are designed to be modular and can be adjusted based on testing results.
