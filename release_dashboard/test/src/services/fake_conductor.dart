// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:conductor_core/src/proto/conductor_state.pb.dart';
import 'package:conductor_ui/services/conductor.dart';
import 'package:file/src/interface/file.dart';
import 'package:file/src/interface/directory.dart';

class FakeConductor extends ConductorService {
  FakeConductor({
    this.testState,
  });

  final ConductorState? testState;

  @override
  Future<void> createRelease(
      {required String candidateBranch,
      required String dartRevision,
      required List<String> engineCherrypickRevisions,
      required String engineMirror,
      required List<String> frameworkCherrypickRevisions,
      required String frameworkMirror,
      required Directory flutterRoot,
      required String incrementLetter,
      required String releaseChannel,
      required File stateFile}) async {}

  @override
  ConductorState? get state {
    return testState;
  }
}
