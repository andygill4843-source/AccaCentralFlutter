import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'app_state.dart';

class SplashScreen extends StatefulWidget {
  final AppState appState;

  const SplashScreen({super.key, required this.appState});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final VideoPlayerController _controller;
  bool _isReady = false;
  bool _hasAdvanced = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/videos/splash_video.mp4');
    _controller
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _isReady = true);
        _controller.play();
      }).catchError((_) {
        // If the video can't load for any reason, don't strand the user
        // on a black screen — just move straight on.
        _advance();
      });
    _controller.addListener(_checkForCompletion);
  }

  void _checkForCompletion() {
    final value = _controller.value;
    if (!value.isInitialized) return;
    if (value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying) {
      _advance();
    }
  }

  void _advance() {
    if (_hasAdvanced || !mounted) return;
    _hasAdvanced = true;
    widget.appState.resolveAuthState();
  }

  @override
  void dispose() {
    _controller.removeListener(_checkForCompletion);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isReady
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}