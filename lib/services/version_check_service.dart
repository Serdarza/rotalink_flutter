import 'dart:io' show Platform;

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/store_links.dart';
import '../data/github_app_version_data_source.dart';
import '../models/app_version_policy.dart';

/// Uygulama sürüm kontrolü — GitHub [versiyon_güncellem.json], yedek Firebase Remote Config.
class VersionCheckService {
  VersionCheckService._();
  static final VersionCheckService instance = VersionCheckService._();

  AppVersionPolicy? _cachedPolicy;

  Future<int> getCurrentVersionCode() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 1;
    } catch (_) {
      return 1;
    }
  }

  Future<AppVersionPolicy?> getVersionPolicy() async {
    _cachedPolicy ??= await GithubAppVersionDataSource.fetchPolicy();
    return _cachedPolicy;
  }

  Future<int> getRemoteVersionCode() async {
    final policy = await getVersionPolicy();
    if (policy != null) {
      if (!kIsWeb && Platform.isIOS) {
        return policy.iosLatestBuild;
      }
      return policy.androidLatestBuild;
    }
    return _remoteConfigVersionCode();
  }

  Future<int> _remoteConfigVersionCode() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      return remoteConfig.getInt('latest_version_code');
    } catch (_) {
      return getCurrentVersionCode();
    }
  }

  Future<bool> isUpdateRequired() async {
    try {
      final currentVersion = await getCurrentVersionCode();
      final remoteVersion = await getRemoteVersionCode();
      return remoteVersion > currentVersion;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getUpdateMessage() async {
    final policy = await getVersionPolicy();
    return policy?.message;
  }

  Future<String> getStoreUrl() async {
    final policy = await getVersionPolicy();
    if (!kIsWeb && Platform.isIOS) {
      return policy?.appStoreUrl ?? StoreLinks.appStore;
    }
    return policy?.playStoreUrl ?? StoreLinks.playStore;
  }

  Future<String> getCurrentVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'Bilinmiyor';
    }
  }
}
