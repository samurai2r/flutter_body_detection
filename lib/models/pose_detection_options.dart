import 'package:flutter/foundation.dart';

class PoseDetectionOptions {
  final bool preferGPU;
  final bool enableSegmentation;
  final bool enableAccuratePoseDetection;
  final bool streamMode;

  const PoseDetectionOptions({
    this.preferGPU = false,
    this.enableSegmentation = false,
    this.enableAccuratePoseDetection = true,
    this.streamMode = false,
  });

  Map<String, dynamic> toMap() => {
    'preferGPU': preferGPU,
    'enableSegmentation': enableSegmentation,
    'enableAccuratePoseDetection': enableAccuratePoseDetection,
    'streamMode': streamMode,
  };

  @override
  String toString() => 'PoseDetectionOptions('
      'preferGPU: $preferGPU, '
      'enableSegmentation: $enableSegmentation, '
      'enableAccuratePoseDetection: $enableAccuratePoseDetection, '
      'streamMode: $streamMode)';
}
