// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:github/github.dart';

import '../proto/internal/scheduler.pb.dart' as pb;

/// Wrapper class around [pb.Target] to support aggregate properties.
///
/// Changes here may also need to be upstreamed in:
///  * https://flutter.googlesource.com/infra/+/refs/heads/main/config/lib/ci_yaml/ci_yaml.star
class Target {
  Target({
    required this.value,
    required this.schedulerConfig,
    required this.slug,
  });

  /// Underlying [Target] this is based on.
  final pb.Target value;

  /// The [SchedulerConfig] [value] is from.
  ///
  /// This is passed for necessary lookups to platform level details.
  final pb.SchedulerConfig schedulerConfig;

  /// The [RepositorySlug] this [Target] is run for.
  final RepositorySlug slug;

  /// Target prefixes that indicate it will run on an ios device.
  static const List<String> iosPlatforms = <String>['mac_ios', 'mac_ios32'];

  /// Gets the assembled properties for this [pb.Target].
  ///
  /// Target properties are prioritized in:
  ///   1. [schedulerConfig.platformProperties]
  ///   2. [pb.Target.properties]
  Map<String, Object> getProperties() {
    final Map<String, Object> platformProperties = _getPlatformProperties();
    final Map<String, Object> properties = _getTargetProperties();
    final Map<String, Object> mergedProperties = <String, Object>{}
      ..addAll(platformProperties)
      ..addAll(properties);

    final List<Dependency> targetDependencies = <Dependency>[];
    if (properties.containsKey('dependencies')) {
      final List<dynamic> rawDeps = properties['dependencies'] as List<dynamic>;
      final Iterable<Dependency> deps = rawDeps.map((dynamic rawDep) => Dependency.fromJson(rawDep as Object));
      targetDependencies.addAll(deps);
    }
    final List<Dependency> platformDependencies = <Dependency>[];
    if (platformProperties.containsKey('dependencies')) {
      final List<dynamic> rawDeps = platformProperties['dependencies'] as List<dynamic>;
      final Iterable<Dependency> deps = rawDeps.map((dynamic rawDep) => Dependency.fromJson(rawDep as Object));
      platformDependencies.addAll(deps);
    }
    // Lookup map to make merging [targetDependencies] and [platformDependencies] simpler.
    final Map<String, Dependency> mergedDependencies = <String, Dependency>{};
    for (Dependency dep in targetDependencies) {
      mergedDependencies[dep.name] = dep;
    }
    for (Dependency dep in platformDependencies) {
      if (!mergedDependencies.containsKey(dep.name)) {
        mergedDependencies[dep.name] = dep;
      }
    }
    mergedProperties['dependencies'] = mergedDependencies.values.map((Dependency dep) => dep.toJson()).toList();

    // xcode is a special property as there's different download policies if its in the devicelab.
    if (properties.containsKey('xcode')) {
      final Object xcodeVersion = <String, Object>{
        'sdk_version': properties['xcode']!,
      };

      if (iosPlatforms.contains(getPlatform())) {
        mergedProperties['\$flutter/devicelab_osx_sdk'] = xcodeVersion;
      } else {
        mergedProperties['\$flutter/osx_sdk'] = xcodeVersion;
      }
    }

    mergedProperties['bringup'] = value.bringup;

    return mergedProperties;
  }

  Map<String, Object> _getTargetProperties() {
    final Map<String, Object> properties = <String, Object>{};
    for (String key in value.properties.keys) {
      properties[key] = _parseProperty(key, value.properties[key]!);
    }

    return properties;
  }

  Map<String, Object> _getPlatformProperties() {
    if (!schedulerConfig.platformProperties.containsKey(getPlatform())) {
      return <String, Object>{};
    }

    final Map<String, String> platformProperties = schedulerConfig.platformProperties[getPlatform()]!.properties;
    final Map<String, Object> properties = <String, Object>{};
    for (String key in platformProperties.keys) {
      properties[key] = _parseProperty(key, platformProperties[key]!);
    }

    return properties;
  }

  /// Converts property strings to their correct type.
  ///
  /// Changes made here should also be made to [_platform_properties] and [_properties] in:
  ///  * https://cs.opensource.google/flutter/infra/+/main:config/lib/ci_yaml/ci_yaml.star
  Object _parseProperty(String key, String value) {
    // Yaml will escape new lines unnecessarily for strings.
    final List<String> newLineIssues = <String>['android_sdk_license', 'android_sdk_preview_license'];
    if (value == 'true') {
      return true;
    } else if (value == 'false') {
      return false;
    } else if (value.startsWith('[')) {
      return jsonDecode(value) as Object;
    } else if (newLineIssues.contains(key)) {
      return value.replaceAll('\\n', '\n');
    } else if (int.tryParse(value) != null) {
      return int.parse(value);
    }

    return value;
  }

  /// Get the platform of this [Target].
  ///
  /// Platform is extracted as the first word in a target's name.
  String getPlatform() {
    return value.name.split(' ').first.toLowerCase();
  }
}

/// Representation of a Flutter dependency.
///
/// See more:
///   * https://flutter.googlesource.com/recipes/+/refs/heads/main/recipe_modules/flutter_deps/api.py
class Dependency {
  Dependency(this.name, this.version);

  /// Constructor for converting from the flutter_deps format.
  factory Dependency.fromJson(Object json) {
    final Map<String, dynamic> map = json as Map<String, dynamic>;
    return Dependency(map['dependency']! as String, map['version'] as String?);
  }

  /// Human readable name of the dependency.
  final String name;

  /// CIPD tag to use.
  ///
  /// If null, will use the version set in the flutter_deps recipe_module.
  final String? version;

  Map<String, Object> toJson() {
    return <String, Object>{
      'dependency': name,
      if (version != null) 'version': version!,
    };
  }
}
