// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:frontend_flutter/auth/membership/capability.dart';
import 'package:frontend_flutter/auth/membership/membership_repository.dart';

class _MembershipServer {
  final HttpServer server;
  int status = 200;
  Map<String, dynamic> body = const {};

  _MembershipServer._(this.server);

  static Future<_MembershipServer> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final holder = _MembershipServer._(server);
    unawaited(
      server.forEach((req) async {
        req.response.statusCode = holder.status;
        req.response.headers.contentType = ContentType.json;
        if (holder.body.isNotEmpty) {
          req.response.write(jsonEncode(holder.body));
        }
        await req.response.close();
      }),
    );
    return holder;
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  late _MembershipServer api;

  setUpAll(() async => api = await _MembershipServer.start());
  tearDownAll(() => api.close());

  MembershipRepository repo() => MembershipRepository(
    BreakdownApi(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${api.server.port}')),
    ),
  );

  const memberBody = {
    'season_id': 'season-1',
    'has_active_costume_role_in_season': true,
    'capabilities': ['upload_continuity_photos', 'assign_costumes'],
  };

  group('fetch (D2 wire contract)', () {
    test(
      '200 → parsed DTO with server-derived capabilities (Ok branch)',
      () async {
        api
          ..status = 200
          ..body = memberBody;
        final result = await repo().fetch('season-1');
        final dto = result.fold((e) => throw e, (d) => d);
        expect(dto.seasonId, 'season-1');
        expect(dto.hasActiveCostumeRoleInSeason, isTrue);
        // The gate reads the server-derived capability list; the client never
        // re-implements has_active_costume_role_in_season.
        expect(dto.canUploadContinuityPhotos, isTrue);
        expect(dto.canAssignCostumes, isTrue);
      },
    );

    test(
      'unknown capability strings are tolerated (additive contract)',
      () async {
        api
          ..status = 200
          ..body = {
            'season_id': 's',
            'has_active_costume_role_in_season': true,
            'capabilities': ['upload_continuity_photos', 'future_capability'],
          };
        final result = await repo().fetch('s');
        final dto = result.fold((e) => throw e, (d) => d);
        // The known gate is enabled by the known cap; the unknown cap is
        // inert (the server remains authoritative). The wire DTO still stores
        // the unknown entry — server-additive extension tolerance.
        expect(dto.canUploadContinuityPhotos, isTrue);
        expect(dto.canAssignCostumes, isFalse);
        expect(dto.capabilities, contains('future_capability'));
      },
    );

    test(
      '403 problem+json carries the stable backend code (Err branch)',
      () async {
        api
          ..status = 403
          ..body = {
            'type': 'https://docs.breakdown.example/problems/season.not-found',
            'title': 'Season not found',
            'status': 403,
            'code': 'season.not-found',
            'trace_id': 'tr-1',
          };
        final result = await repo().fetch('missing');
        final err = result.fold((e) => e, (_) => throw 'expected Left');
        expect(err.code, 'season.not-found');
        expect(err.status, 403);
        // The UI localizes from `code` — never from `detail`.
        expect(err.detail, isNull);
      },
    );

    test(
      'malformed DTO body maps to a transport problem (Err branch)',
      () async {
        api
          ..status = 200
          ..body = {'unexpected': 'shape'};
        final result = await repo().fetch('season-1');
        // The generated client cannot deserialize the body into a
        // SeasonMembershipDto; the failure surfaces as a transport-level Err
        // (never swallowed, AGENTS.md §5) rather than a mis-gated DTO.
        expect(
          result.fold((e) => e.code, (_) => throw 'expected Left'),
          startsWith('transport.'),
        );
      },
    );

    test(
      'connection failure maps to a transport problem (Err branch)',
      () async {
        final dead = MembershipRepository(
          BreakdownApi(dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'))),
        );
        final result = await dead.fetch('season-1');
        expect(
          result.fold((e) => e.code, (_) => throw 'expected Left'),
          startsWith('transport.'),
        );
      },
    );

    test(
      'resolved denial: server-computed false is a resolved denial state',
      () async {
        api
          ..status = 200
          ..body = {
            'season_id': 's',
            'has_active_costume_role_in_season': false,
            'capabilities': const <String>[],
          };
        final dto = (await repo().fetch('s')).fold((e) => throw e, (d) => d);
        expect(dto.hasActiveCostumeRoleInSeason, isFalse);
        expect(dto.canUploadContinuityPhotos, isFalse);
      },
    );
  });
}
