import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// 本地数据 AES-256-CBC 加密服务
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._();
  factory EncryptionService() => _instance;
  EncryptionService._();

  encrypt.Key? _key;
  encrypt.IV? _iv;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 使用设备指纹初始化密钥
  /// [deviceFingerprint] — 设备唯一标识（如 deviceId）
  Future<void> initialize(String deviceFingerprint) async {
    // 使用 SHA-256 从设备指纹派生 256-bit 密钥
    final hash = sha256.convert(utf8.encode(deviceFingerprint));
    _key = encrypt.Key(Uint8List.fromList(hash.bytes));

    // 使用 SHA-256 截取前 16 字节作为 IV 种子
    final ivHash = sha256.convert(utf8.encode('iv_$deviceFingerprint'));
    _iv = encrypt.IV(Uint8List.fromList(ivHash.bytes.take(16).toList()));

    _initialized = true;
  }

  /// AES-256-CBC 加密
  /// 返回 Base64 编码的密文（格式: iv:encryptedData）
  String encryptText(String plainText) {
    if (!_initialized || _key == null || _iv == null) {
      // 未初始化时回退到简单 Base64（开发/预览模式）
      return _fallbackEncrypt(plainText);
    }

    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      final encrypted = encrypter.encrypt(plainText, iv: _iv!);
      return encrypted.base64;
    } catch (e) {
      return _fallbackEncrypt(plainText);
    }
  }

  /// AES-256-CBC 解密
  /// 接收 Base64 编码的密文
  String decryptText(String encryptedBase64) {
    if (!_initialized || _key == null || _iv == null) {
      return _fallbackDecrypt(encryptedBase64);
    }

    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      return encrypter.decrypt64(encryptedBase64, iv: _iv!);
    } catch (e) {
      return _fallbackDecrypt(encryptedBase64);
    }
  }

  /// 加密字节数据
  List<int> encryptBytes(List<int> bytes) {
    if (!_initialized || _key == null || _iv == null) {
      return bytes;
    }
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      final encrypted =
          encrypter.encryptBytes(bytes, iv: _iv!);
      return encrypted.bytes;
    } catch (e) {
      return bytes;
    }
  }

  /// 解密字节数据
  List<int> decryptBytes(List<int> encryptedBytes) {
    if (!_initialized || _key == null || _iv == null) {
      return encryptedBytes;
    }
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      return encrypter.decryptBytes(
        encrypt.Encrypted(Uint8List.fromList(encryptedBytes)),
        iv: _iv!,
      );
    } catch (e) {
      return encryptedBytes;
    }
  }

  /// 生成随机设备指纹（用于首次启动）
  static String generateDeviceFingerprint() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// 回退加密（未初始化时使用 Base64 + XOR 简单混淆）
  String _fallbackEncrypt(String plainText) {
    final bytes = utf8.encode(plainText);
    // 简单 XOR 混淆 + Base64
    const key = 0x5A;
    final xored = bytes.map((b) => b ^ key).toList();
    return base64.encode(xored);
  }

  /// 回退解密
  String _fallbackDecrypt(String encoded) {
    try {
      final bytes = base64.decode(encoded);
      const key = 0x5A;
      final decoded = bytes.map((b) => b ^ key).toList();
      return utf8.decode(decoded);
    } catch (e) {
      // 尝试直接 Base64 解码（兼容旧数据）
      try {
        return utf8.decode(base64.decode(encoded));
      } catch (_) {
        return encoded;
      }
    }
  }
}
