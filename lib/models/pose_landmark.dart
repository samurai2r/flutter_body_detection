import 'dart:ui' show Offset;
import 'pose_landmark_type.dart';

class PoseLandmark {
  final double likelihood;
  final Offset position;
  final PoseLandmarkType type;

  PoseLandmark({
    required this.likelihood,
    required this.position,
    required this.type,
  });

  factory PoseLandmark.fromMap(Map<Object?, Object?> map) {
    try {
      final part = map['part'] as String;
      final x = (map['x'] as num).toDouble();
      final y = (map['y'] as num).toDouble();
      final visibility = (map['visibility'] as num).toDouble();

      return PoseLandmark(
        likelihood: visibility,
        position: Offset(x, y),
        type: PoseLandmarkTypeExtension.fromString(part),
      );
    } catch (e, stackTrace) {
      print('Error parsing landmark data: $e\n$stackTrace');
      throw FormatException('Invalid landmark data format: $map');
    }
  }
}
