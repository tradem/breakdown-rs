// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/membership/capability.dart';

void main() {
  group('Capability.tryParse', () {
    test('maps known wire names to capabilities', () {
      expect(
        Capability.tryParse('upload_continuity_photos'),
        Capability.uploadContinuityPhotos,
      );
      expect(Capability.tryParse('assign_costumes'), Capability.assignCostumes);
    });

    test('tolerates unknown wire names (server-authoritative)', () {
      expect(Capability.tryParse('some_future_capability'), isNull);
    });
  });

  group('SeasonMembershipDto AUTHZ-GATE accessors', () {
    SeasonMembershipDto dto(List<String> caps) => SeasonMembershipDto(
      (b) => b
        ..seasonId = 'season-1'
        ..hasActiveCostumeRoleInSeason = true
        ..capabilities.replace(caps),
    );

    test('canUploadContinuityPhotos reflects the wire capability', () {
      expect(
        dto(['upload_continuity_photos']).canUploadContinuityPhotos,
        isTrue,
      );
      expect(dto(const []).canUploadContinuityPhotos, isFalse);
    });

    test('canAssignCostumes reflects the wire capability', () {
      expect(dto(['assign_costumes']).canAssignCostumes, isTrue);
      expect(dto(const []).canAssignCostumes, isFalse);
    });
  });
}
