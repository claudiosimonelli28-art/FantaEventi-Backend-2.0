import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

final Map<String, ImageProvider> _avatarProviderCache = {};

ImageProvider getAvatarImageProvider(String? avatarUrl) {
  const defaultAvatar = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=400&q=80';
  
  if (avatarUrl == null || avatarUrl.trim().isEmpty) {
    return _avatarProviderCache.putIfAbsent(defaultAvatar, () => const NetworkImage(defaultAvatar));
  }
  
  final url = avatarUrl.trim();
  
  if (_avatarProviderCache.containsKey(url)) {
    return _avatarProviderCache[url]!;
  }
  
  if (url.contains('base64,')) {
    try {
      final cleanB64 = url.substring(url.indexOf('base64,') + 7).trim();
      final bytes = base64Decode(cleanB64);
      final provider = MemoryImage(bytes);
      _avatarProviderCache[url] = provider;
      return provider;
    } catch (_) {
      return _avatarProviderCache.putIfAbsent(defaultAvatar, () => const NetworkImage(defaultAvatar));
    }
  }
  
  if (url.startsWith('http://') || url.startsWith('https://')) {
    final provider = NetworkImage(url);
    _avatarProviderCache[url] = provider;
    return provider;
  }
  
  if ((url.startsWith('/') || url.startsWith('C:') || url.contains('data/user')) && File(url).existsSync()) {
    final provider = FileImage(File(url));
    _avatarProviderCache[url] = provider;
    return provider;
  }
  
  return _avatarProviderCache.putIfAbsent(defaultAvatar, () => const NetworkImage(defaultAvatar));
}

final Map<String, ImageProvider> _coverProviderCache = {};

ImageProvider getEventCoverImageProvider(String? coverUrl) {
  const defaultCover = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=800&q=80';

  if (coverUrl == null || coverUrl.trim().isEmpty) {
    return _coverProviderCache.putIfAbsent(defaultCover, () => const NetworkImage(defaultCover));
  }

  final url = coverUrl.trim();

  if (_coverProviderCache.containsKey(url)) {
    return _coverProviderCache[url]!;
  }

  if (url.contains('base64,')) {
    try {
      final cleanB64 = url.substring(url.indexOf('base64,') + 7).trim();
      final bytes = base64Decode(cleanB64);
      final provider = MemoryImage(bytes);
      _coverProviderCache[url] = provider;
      return provider;
    } catch (_) {
      return _coverProviderCache.putIfAbsent(defaultCover, () => const NetworkImage(defaultCover));
    }
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    final provider = NetworkImage(url);
    _coverProviderCache[url] = provider;
    return provider;
  }

  if ((url.startsWith('/') || url.startsWith('C:') || url.contains('data/user')) && File(url).existsSync()) {
    final provider = FileImage(File(url));
    _coverProviderCache[url] = provider;
    return provider;
  }

  return _coverProviderCache.putIfAbsent(defaultCover, () => const NetworkImage(defaultCover));
}
