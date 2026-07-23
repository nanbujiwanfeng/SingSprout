import 'dart:io';
import 'package:flutter/foundation.dart';

/// 设备检测服务 — 内存、平台、模型适配
class DeviceService {
  static final DeviceService _instance = DeviceService._();
  factory DeviceService() => _instance;
  DeviceService._();

  bool? _isLowMemory;
  String? _platform;

  /// 是否为低配设备（< 2GB 内存）
  bool get isLowMemoryDevice {
    if (_isLowMemory != null) return _isLowMemory!;

    // 移动端通过 /proc/meminfo 检测（仅 Android）
    // iOS 不做检测，默认非低配
    // 桌面/Web 默认非低配
    if (Platform.isAndroid) {
      _isLowMemory = _checkAndroidMemory();
    } else {
      _isLowMemory = false;
    }
    return _isLowMemory!;
  }

  /// 平台标识
  String get platform {
    _platform ??= Platform.operatingSystem;
    return _platform!;
  }

  /// 推荐的 AI 模型名称
  String get recommendedModel {
    return isLowMemoryDevice ? 'singsprout-lite' : 'singsprout-full';
  }

  /// 推荐的模型大小上限（字节）
  int get maxModelSize {
    return isLowMemoryDevice ? 10 * 1024 * 1024 : 50 * 1024 * 1024; // 10MB / 50MB
  }

  /// 读取 Android /proc/meminfo 获取总内存
  bool _checkAndroidMemory() {
    try {
      final file = File('/proc/meminfo');
      if (!file.existsSync()) return false;

      final content = file.readAsStringSync();
      final lines = content.split('\n');
      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          // 格式: MemTotal:       6144000 kB
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final kb = int.tryParse(parts[1]) ?? 0;
            final gb = kb / (1024 * 1024);
            return gb < 2.0; // < 2GB
          }
        }
      }
    } catch (e) {
      debugPrint('DeviceService: Failed to read memory info: $e');
    }
    return false;
  }

  /// 获取设备总内存（GB），用于界面展示
  double get totalMemoryGB {
    if (Platform.isAndroid) {
      try {
        final file = File('/proc/meminfo');
        final content = file.readAsStringSync();
        for (final line in content.split('\n')) {
          if (line.startsWith('MemTotal:')) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]) ?? 0;
              return kb / (1024 * 1024);
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isIOS) {
      // iOS 设备内存通常 >= 2GB（iPhone 6s 起），保守返回 3GB
      return 3.0;
    }
    // 桌面/Web 默认 4GB+
    return 4.0;
  }
}
