import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as path;

Future<void> run(HookContext context) async {
  final rawTagsValue = context.vars['tags'] as String;
  final List<String> tags =
      rawTagsValue.isNotEmpty ? rawTagsValue.split(',') : [];

  final rawExcludeTagsValue = context.vars['exclude-tags'] as String;
  final List<String> excludeTags =
      rawExcludeTagsValue.isNotEmpty ? rawExcludeTagsValue.split(',') : [];

  final packageRoot = context.vars['package-root'];
  final testDir = Directory(path.join(packageRoot, 'test'));

  if (!testDir.existsSync()) {
    context.logger.err('Could not find directory ${testDir.path}');
    exit(1);
  }

  final pubspec = File(path.join(packageRoot, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    context.logger.err('Could not find pubspec.yaml at ${testDir.path}');
    exit(1);
  }

  final pubspecContents = await pubspec.readAsString();
  final flutterSdkRegExp = RegExp(r'sdk:\s*flutter$', multiLine: true);
  final isFlutter = flutterSdkRegExp.hasMatch(pubspecContents);

  var tests = testDir
      .listSync(recursive: true)
      .where((entity) => entity.isTest)
      .filterByTags(tags: tags, excludeTags: excludeTags)
      .map((entity) =>
          path.relative(entity.path, from: testDir.path).replaceAll(r'\', '/'))
      .toList();

  context.vars = {
    'tests': tests,
    'isFlutter': isFlutter,
    'isUsingTags': tags.isNotEmpty,
    'tags': tags,
  };
}

extension on FileSystemEntity {
  bool get isTest {
    return this is File && path.basename(this.path).endsWith('_test.dart');
  }
}

extension on Iterable<FileSystemEntity> {
  Iterable<FileSystemEntity> filterByTags({
    required List<String> tags,
    required List<String> excludeTags,
  }) {
    var filtered = this;
    if (tags.isNotEmpty) {
      filtered = filtered.where(
        (entity) => _hasTags(filePath: entity.path, tags: tags),
      );
    }

    if (excludeTags.isNotEmpty) {
      filtered = filtered.where(
        (element) => !_hasTags(filePath: element.path, tags: excludeTags),
      );
    }

    return filtered;
  }

  bool _hasTags({
    required String filePath,
    required List<String> tags,
  }) {
    const annotationName = 'Tags';

    final compilationUnit = parseFile(
            path: filePath, featureSet: FeatureSet.latestLanguageVersion())
        .unit;

    for (final directive in compilationUnit.directives) {
      final annotations = directive.metadata;

      if (annotations.isNotEmpty) {
        for (final annotation in annotations) {
          if (annotation.name.name == annotationName) {
            try {
              final rawTagsParameter = annotation.arguments?.arguments.first
                      .toSource()
                      .replaceAll("'", '"') ??
                  '';
              final List<dynamic> existingTags = json.decode(rawTagsParameter);

              final hasAnyTag =
                  existingTags.toSet().intersection(tags.toSet()).isNotEmpty;

              if (hasAnyTag) {
                return true;
              }
            } catch (_) {
              continue;
            }
          }
        }
      }
    }

    return false;
  }
}
