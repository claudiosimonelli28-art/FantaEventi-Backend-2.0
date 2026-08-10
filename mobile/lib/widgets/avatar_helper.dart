import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

ImageProvider getAvatarImageProvider(String? avatarUrl) {
  const defaultAvatar = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=400&q=80';
  
  if (avatarUrl == null || avatarUrl.trim().isEmpty) {
    return const NetworkImage(defaultAvatar);
  }
  
  final url = avatarUrl.trim();
  
  if (url.contains('base64,')) {
    try {
      final cleanB64 = url.substring(url.indexOf('base64,') + 7).trim();
      return MemoryImage(base64Decode(cleanB64));
    } catch (_) {
      return const NetworkImage(defaultAvatar);
    }
  }
  
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return NetworkImage(url);
  }
  
  if ((url.startsWith('/') || url.startsWith('C:') || url.contains('data/user')) && File(url).existsSync()) {
    return FileImage(File(url));
  }
  
  return const NetworkImage(defaultAvatar);
}
