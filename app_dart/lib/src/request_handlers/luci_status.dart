// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:googleapis/oauth2/v2.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../model/luci/push_message.dart';
import '../request_handling/body.dart';
import '../request_handling/exceptions.dart';
import '../request_handling/request_handler.dart';
import '../service/buildbucket.dart';
import '../service/config.dart';
import '../service/github_checks_service.dart';
import '../service/logging.dart';
import '../service/luci_build_service.dart';

/// An endpoint for listening to LUCI status updates for scheduled builds.
///
/// The [ScheduleBuildRequest.notify] property is set to tell LUCI to use our
/// PubSub topic. LUCI then publishes updates about build status to that topic,
/// which we listen to on the github-updater subscription. When new messages
/// arrive, they are posted to this web service.
///
/// The PubSub subscription is set up here:
/// https://console.cloud.google.com/cloudpubsub/subscription/detail/github-updater?project=flutter-dashboard
///
/// This endpoing is responsible for updating GitHub with the status of
/// completed builds.
///
/// This currently uses the GitHub Status API, but could be refactored at some
/// point to use the Checks API, which may offer some more knobs to turn
/// on the GitHub page. In particular, it might offer a nice way to retry a
/// failed build - which right now would require removing and re-applying the
/// label, or pushing a new commit.
@immutable
class LuciStatusHandler extends RequestHandler<Body> {
  /// Creates an endpoint for listening to LUCI status updates.
  const LuciStatusHandler(
    Config config,
    this.buildBucketClient,
    this.luciBuildService,
    this.githubChecksService,
  ) : super(config: config);

  final BuildBucketClient buildBucketClient;
  final LuciBuildService luciBuildService;
  final GithubChecksService githubChecksService;

  @override
  Future<Body> post() async {
    RepositorySlug slug;

    if (!await _authenticateRequest(request!.headers)) {
      throw const Unauthorized();
    }
    final String requestString = await utf8.decodeStream(request!);
    log.fine(requestString);
    final PushMessageEnvelope envelope = PushMessageEnvelope.fromJson(
      json.decode(requestString) as Map<String, dynamic>,
    );
    final BuildPushMessage buildPushMessage = BuildPushMessage.fromJson(
        json.decode(String.fromCharCodes(base64.decode(envelope.message!.data!))) as Map<String, dynamic>);
    final Build build = buildPushMessage.build!;
    final String builderName = build.tagsByName('builder').single;
    log.fine('Available tags: ${build.tags.toString()}');
    // Skip status update if we can not get the sha tag.
    if (build.tagsByName('buildset').isEmpty) {
      log.warning('Buildset tag not included, skipping Status Updates');
      return Body.empty;
    }
    log.fine('Setting status: ${buildPushMessage.toJson()} for $builderName');
    final Map<String, dynamic>? userData = jsonDecode(buildPushMessage.userData!) as Map<String, dynamic>?;
    if (userData != null && userData.containsKey('repo_owner') && userData.containsKey('repo_name')) {
      // Message is coming from a github checks api enabled repo. We need to
      // create the slug from the data in the message and send the check status
      // update.
      slug = RepositorySlug(
        userData['repo_owner'] as String,
        userData['repo_name'] as String,
      );
      await githubChecksService.updateCheckStatus(
        buildPushMessage,
        luciBuildService,
        slug,
      );
    } else {
      log.shout('This repo does not support checks API');
    }
    return Body.empty;
  }

  Future<bool> _authenticateRequest(HttpHeaders headers) async {
    final http.Client client = httpClient!;
    final Oauth2Api oauth2api = Oauth2Api(client);
    final String? idToken = headers.value(HttpHeaders.authorizationHeader);
    if (idToken == null || !idToken.startsWith('Bearer ')) {
      return false;
    }
    final Tokeninfo info = await oauth2api.tokeninfo(
      idToken: idToken.substring('Bearer '.length),
    );
    if (info.expiresIn == null || info.expiresIn! < 1) {
      return false;
    }
    final Set<String> allowedServiceAccounts = <String>{
      'flutter-devicelab@flutter-dashboard.iam.gserviceaccount.com',
      'flutter-dashboard@appspot.gserviceaccount.com'
    };
    return allowedServiceAccounts.contains(info.email);
  }
}
