import 'package:flutter/material.dart';
import 'package:body_detection/body_detection.dart';

/// Test app to validate CI::complete_intermediate crash fixes
/// 
/// This app runs continuous pose detection and preview generation
/// to stress test the new implementation and verify crash fixes.
class CIFixesTestApp extends StatefulWidget {
  @override
  _CIFixesTestAppState createState() => _CIFixesTestAppState();
}

class _CIFixesTestAppState extends State<CIFixesTestApp> {
  bool _isDetecting = false;
  int _poseCount = 0;
  int _previewCount = 0;
  DateTime? _startTime;
  String _status = 'Ready to test';

  @override
  void initState() {
    super.initState();
    _initializeBodyDetection();
  }

  Future<void> _initializeBodyDetection() async {
    try {
      await BodyDetection.enablePoseDetection();
      setState(() {
        _status = 'Body detection initialized';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to initialize: $e';
      });
    }
  }

  Future<void> _startStressTest() async {
    if (_isDetecting) return;

    setState(() {
      _isDetecting = true;
      _poseCount = 0;
      _previewCount = 0;
      _startTime = DateTime.now();
      _status = 'Running stress test...';
    });

    try {
      await BodyDetection.startCameraStream();
      
      // Listen to the camera stream
      BodyDetection.poseStream.listen((pose) {
        if (mounted) {
          setState(() {
            _poseCount++;
          });
        }
      });

      BodyDetection.imageStream.listen((image) {
        if (mounted) {
          setState(() {
            _previewCount++;
          });
        }
      });

    } catch (e) {
      setState(() {
        _status = 'Failed to start camera: $e';
        _isDetecting = false;
      });
    }
  }

  Future<void> _stopStressTest() async {
    if (!_isDetecting) return;

    try {
      await BodyDetection.stopCameraStream();
      setState(() {
        _isDetecting = false;
        _status = 'Test completed';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to stop camera: $e';
      });
    }
  }

  String _getTestDuration() {
    if (_startTime == null) return '0s';
    final duration = DateTime.now().difference(_startTime!);
    return '${duration.inSeconds}s';
  }

  double _getPoseRate() {
    if (_startTime == null) return 0.0;
    final duration = DateTime.now().difference(_startTime!);
    if (duration.inSeconds == 0) return 0.0;
    return _poseCount / duration.inSeconds;
  }

  double _getPreviewRate() {
    if (_startTime == null) return 0.0;
    final duration = DateTime.now().difference(_startTime!);
    if (duration.inSeconds == 0) return 0.0;
    return _previewCount / duration.inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CI Crash Fixes Test'),
        backgroundColor: _isDetecting ? Colors.green : Colors.blue,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: $_status', style: TextStyle(fontSize: 16)),
                    SizedBox(height: 8),
                    Text('Test Duration: ${_getTestDuration()}'),
                    Text('Poses Detected: $_poseCount'),
                    Text('Preview Frames: $_previewCount'),
                    Text('Pose Rate: ${_getPoseRate().toStringAsFixed(1)} fps'),
                    Text('Preview Rate: ${_getPreviewRate().toStringAsFixed(1)} fps'),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isDetecting ? null : _startStressTest,
                    child: Text('Start Stress Test'),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isDetecting ? _stopStressTest : null,
                    child: Text('Stop Test'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Expanded(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Test Instructions:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('1. Start the stress test and let it run for 10+ minutes'),
                      Text('2. Monitor for any CI::complete_intermediate crashes'),
                      Text('3. Check that pose detection rate stays consistent'),
                      Text('4. Verify preview rate is ~10 fps (throttled)'),
                      Text('5. Monitor memory usage in Xcode Instruments'),
                      SizedBox(height: 16),
                      Text('Expected Results:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('• No crashes during extended testing'),
                      Text('• Consistent pose detection (~30 fps)'),
                      Text('• Throttled preview (~10 fps)'),
                      Text('• Stable memory usage'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_isDetecting) {
      BodyDetection.stopCameraStream();
    }
    super.dispose();
  }
}

void main() {
  runApp(MaterialApp(
    home: CIFixesTestApp(),
    title: 'CI Crash Fixes Test',
  ));
}
