import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

class AlertService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playPassengerAlert() async {
    try {
      await _player.stop();
      await _player.setAsset('assets/sounds/alert.mp3');
      await _player.play();
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }

    final canVibrate = await Vibration.hasVibrator() ?? false;
    if (canVibrate) {
      await Vibration.vibrate(pattern: [0, 180, 80, 180]);
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}