import 'dart:convert';
import 'dart:math';

/// QR code generation service for family invites
class QrInviteService {
  static const Duration qrCodeValidity = Duration(hours: 24);
  static const Set<String> _validRoles = {'senior', 'family'};

  /// Generate a time-limited QR code payload
  /// Returns base64 encoded JSON (simple encoding for now)
  ///
  /// Throws [ArgumentError] if userId is empty or userRole is invalid
  String generateInviteQrData(String userId, String userRole) {
    final trimmedUserId = userId.trim();
    final trimmedRole = userRole.trim().toLowerCase();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID cannot be empty');
    }

    if (!_validRoles.contains(trimmedRole)) {
      throw ArgumentError.value(
        userRole,
        'userRole',
        'Role must be one of: ${_validRoles.join(", ")}',
      );
    }

    final payload = {
      'uid': trimmedUserId,
      'role': trimmedRole,
      'exp': DateTime.now().add(qrCodeValidity).millisecondsSinceEpoch,
      'nonce': _generateNonce(),
    };

    // Simple base64 encoding
    // TODO: Add proper encryption for production
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  /// Validate and decode a scanned QR code
  /// Returns null if data is invalid or expired
  InvitePayload? validateQrData(String encodedData) {
    try {
      final decoded = utf8.decode(base64Decode(encodedData));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final payload = InvitePayload.fromJson(json);

      // Check if expired
      if (payload.isExpired) {
        return null;
      }

      return payload;
    } on FormatException {
      // Invalid JSON or missing required fields
      return null;
    } catch (e) {
      // Invalid QR data (base64, utf8, etc.)
      return null;
    }
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }
}

/// Decoded invite payload from QR code
class InvitePayload {
  final String uid;
  final String role;
  final int exp;
  final String nonce;

  InvitePayload({
    required this.uid,
    required this.role,
    required this.exp,
    required this.nonce,
  });

  /// Parse from JSON, throws [FormatException] if required fields are missing
  factory InvitePayload.fromJson(Map<String, dynamic> json) {
    // Validate required fields exist and have correct types
    if (!json.containsKey('uid') || json['uid'] is! String) {
      throw const FormatException('Missing or invalid "uid" field');
    }
    if (!json.containsKey('role') || json['role'] is! String) {
      throw const FormatException('Missing or invalid "role" field');
    }
    if (!json.containsKey('exp') || json['exp'] is! int) {
      throw const FormatException('Missing or invalid "exp" field');
    }
    if (!json.containsKey('nonce') || json['nonce'] is! String) {
      throw const FormatException('Missing or invalid "nonce" field');
    }

    final uid = json['uid'] as String;
    final role = json['role'] as String;

    if (uid.isEmpty) {
      throw const FormatException('Field "uid" cannot be empty');
    }
    if (role.isEmpty) {
      throw const FormatException('Field "role" cannot be empty');
    }

    return InvitePayload(
      uid: uid,
      role: role,
      exp: json['exp'] as int,
      nonce: json['nonce'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'role': role,
      'exp': exp,
      'nonce': nonce,
    };
  }

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > exp;

  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch(exp);
}
