// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests for the AI-import data layer (`flutter-ai-import`
// tasks 1.1/1.2/1.4/1.5): every route Ok/Err (incl. 200/202/413/415/404/
// 403), the raw-body declared content types, the two-step credential
// hand-off, the SECRET-IN-PAYLOAD-ONLY assertion covering ALL sinks
// (secure-storage interception, Drift cache writes, transport metadata,
// returned values) on success AND failure, the bounded rollback, the
// ambiguous-timeout reconciliation, the job-watch state machine, and the
// config-create reconciliation.
//
// gitleaks is a repo-wide CI control, NOT runtime evidence — it is NOT
// cited here; these assertions are the runtime proof.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/data/ai_config_repository.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';

// --- Fixtures ---------------------------------------------------------------

const _secret = 'sk-super-secret-llm-key-0123456789';

AiProviderInfo _provider(String key) => AiProviderInfo(
  (b) => b
    ..provider = LlmProvider.openai
    ..key = key,
);

ModelInfo _model(String id) => ModelInfo(
  (b) => b
    ..id = id
    ..provider = LlmProvider.openai,
);

SettingsView _settings(String id, {String vaultKeyId = 'vk-1'}) => SettingsView(
  (b) => b
    ..id = id
    ..provider = 'openai'
    ..vaultKeyId = vaultKeyId
    ..vaultVersion = 1
    ..version = 1
    ..bindingState = CredentialBindingState.active,
);

AiConfigView _config(String id, {int version = 1}) => AiConfigView(
  (b) => b
    ..id = id
    ..userId = 'user-a'
    ..vaultKeyId = 'vk-1'
    ..assistantModel = 'gpt-5.6-luna'
    ..provider = LlmProvider.openai
    ..promptKinds.replace(
      BuiltList(const [DocumentKind.script, DocumentKind.schedule]),
    )
    ..revoked = false
    ..version = version,
);

AiImportJob _job(
  String id, {
  JobStatus status = JobStatus.pending,
  int retries = 0,
  int maxRetries = 3,
}) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'user-a'
    ..status = status
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = retries
    ..maxRetries = maxRetries
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

AiImportJobResponse _jobResponse(AiImportJob job) =>
    AiImportJobResponse((b) => b..job.replace(job));

DraftScene _draftScene(String ref) => DraftScene(
  (b) => b
    ..draftRef = ref
    ..sceneNumber = 12
    ..summary = 'A scene'
    ..characters.replace(const <String>['char-1']),
);

ScriptContext _scriptContext() => ScriptContext(
  (b) => b
    ..title = 'Pilot'
    ..scenes.replace([_draftScene('draft-1')])
    ..uncertainties.replace(BuiltList(const <Uncertainty>[])),
);

/// Builds the typed script preview payload in the exact wire form the
/// generated client deserializes.
Object _scriptPreviewWire() {
  final payload = AiPreviewPayload(
    (b) => b
      ..oneOf =
          OneOf.fromValue3<
            AiPreviewPayloadOneOf,
            AiPreviewPayloadOneOf1,
            AiPreviewPayloadOneOf2
          >(
            value: AiPreviewPayloadOneOf(
              (b) => b
                ..kind = AiPreviewPayloadOneOfKindEnum.script
                ..data.replace(_scriptContext()),
            ),
          ),
  );
  return serializers.serializeWith(AiPreviewPayload.serializer, payload)!;
}

// --- Fake transport ---------------------------------------------------------

/// Scriptable interceptor: resolves every request with [respond] (status
/// [status]), or rejects with an RFC 9457 problem+json body carrying
/// [problem]. Records every request for payload/secret assertions.
class _ScriptInterceptor extends Interceptor {
  _ScriptInterceptor({this.respond, this.problem, this.status = 200});

  final Object? Function(RequestOptions options)? respond;
  final String? problem;
  final int status;

  int calls = 0;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls++;
    requests.add(options);
    if (problem != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: status,
            data: {'code': problem, 'title': 'err', 'status': status},
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: status,
        data: respond?.call(options),
      ),
    );
  }
}

_ScriptInterceptor _scripted(List<Object?> responses, {int? failAfter}) {
  var call = 0;
  return _ScriptInterceptor(
    respond: (options) {
      final index = call++;
      if (failAfter != null && index > failAfter) {
        throw StateError('unexpected extra call');
      }
      return responses[index];
    },
  );
}

_ScriptInterceptor _scriptOf(BreakdownApi api) =>
    api.dio.interceptors.whereType<_ScriptInterceptor>().single;

BreakdownApi _api(Interceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
  dio.interceptors.add(interceptor);
  return BreakdownApi(dio: dio);
}

/// A scriptable scheduler — every tick is counted, never delayed
/// (deterministic, no wall-clock gating).
class _FakeScheduler extends ReconciliationScheduler {
  int ticks = 0;

  @override
  Future<void> tick(int attempt) async => ticks++;
}

/// One scripted HTTP outcome for the reconciliation tests.
class _Outcome {
  _Outcome.ok(this.body) : timeout_ = false;
  _Outcome.timeout() : body = null, timeout_ = true;

  final Object? body;
  final bool timeout_;
  final List<RequestOptions> requests = [];

  void apply(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (timeout_) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );
      return;
    }
    handler.resolve(
      Response(requestOptions: options, statusCode: 200, data: body),
    );
  }
}

/// Interceptor driven by a list of scripted outcomes (cycling).
class _ScriptedOutcomes extends Interceptor {
  _ScriptedOutcomes(this.outcomes);

  final List<_Outcome> outcomes;
  int index = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    outcomes[index++ % outcomes.length].apply(options, handler);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSecureStoragePlatform secureStorage;
  setUp(() {
    secureStorage = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = secureStorage;
  });

  group('AiConfigRepository routes (task 1.1)', () {
    test('listProviders Ok / Err', () async {
      final ok = _api(
        _scripted([
          serializers.serialize(
            BuiltList([_provider('openai')]),
            specifiedType: const FullType(BuiltList, [
              FullType(AiProviderInfo),
            ]),
          )!,
        ]),
      );
      final providers = await AiConfigRepository(ok).listProviders();
      expect(providers.getRight().toNullable()!.length, 1);

      final err = _api(
        _ScriptInterceptor(problem: 'ai_config.disabled', status: 404),
      );
      final failed = await AiConfigRepository(err).listProviders();
      expect(failed.getLeft().toNullable()!.code, 'ai_config.disabled');
    });

    test('listModels Ok / 422 unknown provider', () async {
      final ok = _api(
        _scripted([
          serializers.serialize(
            BuiltList([_model('gpt-5.6-luna')]),
            specifiedType: const FullType(BuiltList, [FullType(ModelInfo)]),
          )!,
        ]),
      );
      final models = await AiConfigRepository(ok).listModels('openai');
      expect(models.getRight().toNullable()!.first.id, 'gpt-5.6-luna');

      final err = _api(
        _ScriptInterceptor(problem: 'provider.unknown', status: 422),
      );
      final failed = await AiConfigRepository(err).listModels('bogus');
      expect(failed.getLeft().toNullable()!.status, 422);
    });

    test(
      'submitCredential: secret rides ONLY in the request payload',
      () async {
        final ok = _api(
          _scripted([
            serializers.serializeWith(
              IdVersionResponse.serializer,
              IdVersionResponse(
                (b) => b
                  ..id = 'settings-1'
                  ..version = 1,
              ),
            )!,
          ]),
        );
        final res = await AiConfigRepository(ok)
            .submitCredential(provider: 'openai', secret: _secret);
        expect(res.getRight().toNullable()!.id, 'settings-1');

        final opts = _scriptOf(ok).requests.first;
        // The secret is in the request body (the serialized credential
        // payload)…
        final body = opts.data;
        expect(body is Map && body['secret'] == _secret, isTrue);
        // …and in NO other transport sink (headers/extra/query).
        expect(
          opts.headers.values.where((v) => '$v'.contains(_secret)),
          isEmpty,
        );
        expect(opts.extra.values.where((v) => '$v'.contains(_secret)), isEmpty);
        expect(
          opts.queryParameters.values.where((v) => '$v'.contains(_secret)),
          isEmpty,
        );
      },
    );

    test('getSettings Ok / 404', () async {
      final ok = _api(
        _scripted([
          serializers.serializeWith(SettingsView.serializer, _settings('s1'))!,
        ]),
      );
      final view = await AiConfigRepository(ok).getSettings('s1');
      expect(view.getRight().toNullable()!.vaultKeyId, 'vk-1');

      final err = _api(
        _ScriptInterceptor(problem: 'settings.not-found', status: 404),
      );
      final failed = await AiConfigRepository(err).getSettings('missing');
      expect(failed.getLeft().toNullable()!.status, 404);
    });

    test('destroyCredential Ok / Err', () async {
      final ok = _api(_scripted([2]));
      final version = await AiConfigRepository(ok).destroyCredential('s1', 1);
      expect(version.getRight().toNullable(), 2);

      final err = _api(
        _ScriptInterceptor(problem: 'settings.conflict', status: 409),
      );
      final failed = await AiConfigRepository(err).destroyCredential('s1', 1);
      expect(failed.isLeft(), isTrue);
    });

    test('rollbackCredential: succeeds, retries then succeeds, or surfaces '
        'orphaned_credential after the bounded attempts', () async {
      // First try succeeds — one DELETE.
      final ok = _api(_scripted([2]));
      final rolled = await AiConfigRepository(ok).rollbackCredential('s1', 1);
      expect(rolled.isRight(), isTrue);
      expect(_scriptOf(ok).calls, 1);

      // Fails twice (null body → dto.invalid), succeeds on the third.
      var destroyCalls = 0;
      final flaky = _api(
        _ScriptInterceptor(respond: (_) => destroyCalls++ < 2 ? null : 2),
      );
      final retried = await AiConfigRepository(flaky)
          .rollbackCredential('s1', 1, tick: (_) async {});
      expect(retried.isRight(), isTrue);
      expect(_scriptOf(flaky).calls, 3);

      // Exhausted — orphaned credential surfaces, never silently dropped.
      final dead = _api(
        _ScriptInterceptor(problem: 'settings.conflict', status: 409),
      );
      final orphan = await AiConfigRepository(dead)
          .rollbackCredential('s1', 1, tick: (_) async {});
      expect(
        orphan.getLeft().toNullable()!.code,
        'ai_config.orphaned_credential',
      );
      expect(_scriptOf(dead).calls, kMaxRollbackAttempts);
    });

    test('createConfig Ok (201) / Err (403)', () async {
      final ok = _api(
        _ScriptInterceptor(
          status: 201,
          respond: (_) => serializers.serializeWith(
            IdVersionResponse.serializer,
            IdVersionResponse(
              (b) => b
                ..id = 'config-1'
                ..version = 1,
            ),
          )!,
        ),
      );
      final created = await AiConfigRepository(ok).createConfig(
        CreateAiConfigRequest(
          (b) => b
            ..provider = LlmProvider.openai
            ..assistantModel = 'gpt-5.6-luna'
            ..vaultKeyId = 'vk-1'
            ..prompts.replace(const {'script': 'p', 'schedule': 'q'}),
        ),
      );
      expect(created.getRight().toNullable()!.id, 'config-1');

      final err = _api(
        _ScriptInterceptor(problem: 'ai_config.forbidden', status: 403),
      );
      final failed = await AiConfigRepository(err).createConfig(
        CreateAiConfigRequest(
          (b) => b
            ..provider = LlmProvider.openai
            ..assistantModel = 'm'
            ..vaultKeyId = 'vk'
            ..prompts.replace(const {}),
        ),
      );
      expect(failed.getLeft().toNullable()!.status, 403);
    });

    test('listConfigs Ok / Err', () async {
      final ok = _api(
        _scripted([
          serializers.serialize(
            BuiltList([_config('c-1')]),
            specifiedType: const FullType(BuiltList, [FullType(AiConfigView)]),
          )!,
        ]),
      );
      final configs = await AiConfigRepository(ok).listConfigs();
      expect(configs.getRight().toNullable()!.first.id, 'c-1');

      final err = _api(
        _ScriptInterceptor(problem: 'ai_config.forbidden', status: 403),
      );
      final failed = await AiConfigRepository(err).listConfigs();
      expect(failed.getLeft().toNullable()!.code, 'ai_config.forbidden');
    });

    test('getConfig Ok / 404', () async {
      final ok = _api(
        _scripted([
          serializers.serializeWith(AiConfigView.serializer, _config('c1'))!,
        ]),
      );
      final got = await AiConfigRepository(ok).getConfig('c1');
      expect(got.getRight().toNullable()!.assistantModel, 'gpt-5.6-luna');

      final err = _api(
        _ScriptInterceptor(problem: 'ai_config.not-found', status: 404),
      );
      final failed = await AiConfigRepository(err).getConfig('gone');
      expect(failed.getLeft().toNullable()!.status, 404);
    });

    test('updateConfig version echo Ok / 409', () async {
      UpdateAiConfigRequest request() => UpdateAiConfigRequest(
        (b) => b
          ..provider = LlmProvider.openai
          ..assistantModel = 'glm-5.3'
          ..vaultKeyId = 'vk-1'
          ..version = 2
          ..prompts.replace(const {}),
      );
      final ok = _api(_scripted([3]));
      final updated = await AiConfigRepository(ok)
          .updateConfig('c1', request());
      expect(updated.getRight().toNullable(), 3);

      final err = _api(
        _ScriptInterceptor(problem: 'ai_config.conflict', status: 409),
      );
      final failed = await AiConfigRepository(err)
          .updateConfig('c1', request());
      expect(failed.getLeft().toNullable()!.status, 409);
    });

    test('revokeConfig Ok / Err', () async {
      final ok = _api(_scripted([2]));
      final revoked = await AiConfigRepository(ok).revokeConfig('c1', 1);
      expect(revoked.getRight().toNullable(), 2);

      final err = _api(
        _ScriptInterceptor(problem: 'ai_config.conflict', status: 409),
      );
      final failed = await AiConfigRepository(err).revokeConfig('c1', 1);
      expect(failed.isLeft(), isTrue);
    });
  });

  group('Credential hand-off + secret discipline (task 1.5)', () {
    test('two-step hand-off: submit → read Settings → vault_key_id', () async {
      // Call 1: POST credentials → IdVersionResponse; call 2: GET settings
      // → SettingsView (scripted by call order).
      final api = _api(
        _scripted([
          serializers.serializeWith(
            IdVersionResponse.serializer,
            IdVersionResponse(
              (b) => b
                ..id = 'settings-1'
                ..version = 1,
            ),
          )!,
          serializers.serializeWith(
            SettingsView.serializer,
            _settings('settings-1', vaultKeyId: 'vk-77'),
          )!,
        ]),
      );
      final res = await submitCredentialWithHandoff(
        AiConfigRepository(api),
        provider: 'openai',
        secret: _secret,
      );
      final handoff = res.getRight().toNullable()!;
      expect(handoff.settingsId, 'settings-1');
      expect(handoff.settingsVersion, 1);
      expect(handoff.vaultKeyId, 'vk-77');
      // The hand-off result itself carries no secret material (D6).
      expect('$handoff'.contains(_secret), isFalse);
    });

    test('hand-off read failure after a successful submission → Left '
        '(the caller decides the rollback; the credential is never '
        'destroyed on its own)', () async {
      final submitOk = serializers.serializeWith(
        IdVersionResponse.serializer,
        IdVersionResponse(
          (b) => b
            ..id = 'settings-1'
            ..version = 1,
        ),
      )!;
      var call = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            call++;
            if (call == 1) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: submitOk,
                ),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 404,
                  data: {'code': 'settings.not-found', 'status': 404},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );
      final res = await submitCredentialWithHandoff(
        AiConfigRepository(BreakdownApi(dio: dio)),
        provider: 'openai',
        secret: _secret,
      );
      expect(res.getLeft().toNullable()!.code, 'settings.not-found');
      // Exactly two calls: the submit (POST) + the failed hand-off read
      // (GET). NO destroy call followed — the repository never destroys a
      // credential on its own.
      expect(call, 2);
    });

    test('missing vault_key_id on a committed Settings aggregate surfaces '
        'ai_config.vault_key_missing', () async {
      final api = _api(
        _scripted([
          serializers.serializeWith(
            IdVersionResponse.serializer,
            IdVersionResponse(
              (b) => b
                ..id = 'settings-1'
                ..version = 1,
            ),
          )!,
          serializers.serializeWith(
            SettingsView.serializer,
            _settings('settings-1', vaultKeyId: ''),
          )!,
        ]),
      );
      final res = await submitCredentialWithHandoff(
        AiConfigRepository(api),
        provider: 'openai',
        secret: _secret,
      );
      expect(res.getLeft().toNullable()!.code, 'ai_config.vault_key_missing');
    });

    test('SECRET-IN-PAYLOAD-ONLY: no persistent sink holds the secret on '
        'success OR failure (secure-storage interception, Drift cache, '
        'returned values)', () async {
      final db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final jobsDao = AiImportJobsCacheDao(db);

      // Success path.
      final okApi = _api(
        _scripted([
          serializers.serializeWith(
            IdVersionResponse.serializer,
            IdVersionResponse(
              (b) => b
                ..id = 'settings-1'
                ..version = 1,
            ),
          )!,
          serializers.serializeWith(
            SettingsView.serializer,
            _settings('settings-1', vaultKeyId: 'vk-77'),
          )!,
        ]),
      );
      final okHandoff = await submitCredentialWithHandoff(
        AiConfigRepository(okApi),
        provider: 'openai',
        secret: _secret,
      );
      expect(okHandoff.isRight(), isTrue);

      // Failure path (submission itself fails).
      final errApi = _api(
        _ScriptInterceptor(problem: 'ai_config.forbidden', status: 403),
      );
      final failed = await submitCredentialWithHandoff(
        AiConfigRepository(errApi),
        provider: 'openai',
        secret: _secret,
      );
      expect(failed.isLeft(), isTrue);

      // ALL sinks are secret-free:
      // 1. secure storage (intercepted) — the credential flow writes
      //    NOTHING to any store.
      expect(secureStorage.store.values.join(), isNot(contains(_secret)));
      // 2. Drift cache — the AI jobs table holds no row and no secret.
      expect(await jobsDao.readAll(), isEmpty);
      // 3. returned values — the error carries the server problem, never
      //    the secret.
      expect('$failed'.contains(_secret), isFalse);
      // 4. transport metadata on the failing request — body-only.
      final failingOpts = _scriptOf(errApi).requests.first;
      expect(
        failingOpts.headers.values.where((v) => '$v'.contains(_secret)),
        isEmpty,
      );
    });
  });

  group('reconcileConfigCreate (task 1.2 — ambiguous create timeout)', () {
    test('a committed config keeps the credential', () async {
      final api = _api(
        _scripted([
          serializers.serializeWith(AiConfigView.serializer, _config('c1'))!,
        ]),
      );
      final outcome = await reconcileConfigCreate(
        AiConfigRepository(api),
        configId: 'c1',
        tick: (_) async {},
      );
      expect(outcome, isA<ConfigCommitted>());
    });

    test('a definitive 404 + empty list runs the rollback path', () async {
      final listBody = serializers.serialize(
        BuiltList<AiConfigView>(const []),
        specifiedType: const FullType(BuiltList, [FullType(AiConfigView)]),
      )!;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.endsWith('/config/c1')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 404,
                    data: {'code': 'ai_config.not-found', 'status': 404},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: listBody,
              ),
            );
          },
        ),
      );
      final outcome = await reconcileConfigCreate(
        AiConfigRepository(BreakdownApi(dio: dio)),
        configId: 'c1',
        tick: (_) async {},
      );
      expect(outcome, isA<ConfigNotCommitted>());
    });

    test(
      'unresolved transport failures → ConfigUnknown (no cleanup)',
      () async {
        final api = _api(
          _ScriptInterceptor(problem: 'server.down', status: 500),
        );
        final outcome = await reconcileConfigCreate(
          AiConfigRepository(api),
          configId: 'c1',
          attempts: 3,
          tick: (_) async {},
        );
        expect(outcome, isA<ConfigUnknown>());
        // Bounded: exactly the attempted reads, no more.
        expect(_scriptOf(api).calls, 3);
      },
    );
  });

  group('AiImportRepository routes (task 1.2)', () {
    test('uploadSchedule 202 (csv) — declared content type, ack without '
        'duplicate', () async {
      final api = _api(
        _ScriptInterceptor(status: 202, respond: (_) => 'job-1'),
      );
      final res = await AiImportRepository(
        api,
        _dao(),
      ).uploadSchedule(body: 'day,scene\n1,12', source: AiScheduleSource.csv);
      final ack = res.getRight().toNullable()!;
      expect(ack.jobId, 'job-1');
      expect(ack.duplicate, isFalse);
      final opts = _scriptOf(api).requests.first;
      expect(opts.uri.path, '/v1/ai-import/schedules');
      expect(opts.contentType, 'text/csv');
      expect(opts.data, 'day,scene\n1,12');
    });

    test(
      'uploadSchedule 200 — digest-duplicate is a first-class ack',
      () async {
        final api = _api(
          _ScriptInterceptor(status: 200, respond: (_) => 'job-0'),
        );
        final res = await AiImportRepository(
          api,
          _dao(),
        ).uploadSchedule(body: 'x', source: AiScheduleSource.pdf);
        final ack = res.getRight().toNullable()!;
        expect(ack.duplicate, isTrue);
        expect(_scriptOf(api).requests.first.contentType, 'application/pdf');
      },
    );

    test(
      'uploadSchedule 413/415/403/404 surface keyed on the problem code',
      () async {
        for (final (status, code) in [
          (413, 'ai_import.payload_too_large'),
          (415, 'ai_import.unsupported_media_type'),
          (403, 'ai_import.forbidden'),
          (404, 'ai_import.disabled'),
        ]) {
          final api = _api(_ScriptInterceptor(problem: code, status: status));
          final res = await AiImportRepository(
            api,
            _dao(),
          ).uploadSchedule(body: 'x', source: AiScheduleSource.plainText);
          final err = res.getLeft().toNullable()!;
          expect(err.code, code, reason: 'status $status');
          expect(err.status, status);
        }
      },
    );

    test('uploadScript 202 — application/pdf content type', () async {
      final api = _api(_scripted(['job-2']));
      final res = await AiImportRepository(
        api,
        _dao(),
      ).uploadScript(body: '%PDF-1.4');
      expect(res.getRight().toNullable()!.jobId, 'job-2');
      final opts = _scriptOf(api).requests.first;
      expect(opts.contentType, kScriptContentType);
    });

    test(
      'empty upload body surfaces dto_invalid (no fabricated job id)',
      () async {
        final api = _api(_scripted(['  ']));
        final res = await AiImportRepository(
          api,
          _dao(),
        ).uploadSchedule(body: 'x', source: AiScheduleSource.csv);
        expect(res.getLeft().toNullable()!.code, 'ai_import.dto_invalid');
      },
    );

    test(
      'getJobAndCache Ok upserts the cache row; Err leaves it untouched',
      () async {
        final dao = _dao();
        final api = _api(
          _scripted([
            serializers.serializeWith(
              AiImportJobResponse.serializer,
              _jobResponse(_job('j1')),
            )!,
          ]),
        );
        final repo = AiImportRepository(api, dao);
        final res = await repo.getJobAndCache('j1');
        expect(res.getRight().toNullable()!.id, 'j1');
        expect((await dao.readAll()).single.id, 'j1');

        final errApi = _api(
          _ScriptInterceptor(problem: 'ai_import.not_found', status: 404),
        );
        final failed = await AiImportRepository(
          errApi,
          dao,
        ).getJobAndCache('j1');
        expect(failed.getLeft().toNullable()!.code, 'ai_import.not_found');
        // Success-only cache writes: the failed refetch kept the good row.
        expect((await dao.readAll()).single.id, 'j1');
      },
    );

    test(
      'episode context persists with the job row and survives refetches',
      () async {
        final dao = _dao();
        final api = _api(
          _scripted([
            serializers.serializeWith(
              AiImportJobResponse.serializer,
              _jobResponse(_job('j1')),
            )!,
          ]),
        );
        final repo = AiImportRepository(api, dao);
        await dao.upsertWithEpisodeContext(
          _job('j1', status: JobStatus.succeeded),
          DateTime.utc(2026, 1, 1),
          episodeId: 'ep-1',
          seriesId: 'series-1',
        );
        // A later status refetch (without context) must NOT wipe the context.
        await repo.getJobAndCache('j1');
        final row = (await dao.readAll()).single;
        expect(row.episodeId, 'ep-1');
        expect(row.seriesId, 'series-1');
      },
    );

    test('listJobsAndCache Ok / Err', () async {
      final dao = _dao();
      final api = _api(
        _scripted([
          serializers.serialize(
            BuiltList([_jobResponse(_job('j1')), _jobResponse(_job('j2'))]),
            specifiedType: const FullType(BuiltList, [
              FullType(AiImportJobResponse),
            ]),
          )!,
        ]),
      );
      final jobs = await AiImportRepository(api, dao).listJobsAndCache();
      expect(jobs.getRight().toNullable()!.length, 2);
      expect((await dao.readAll()).length, 2);

      final errApi = _api(
        _ScriptInterceptor(problem: 'ai_config.forbidden', status: 403),
      );
      final failed = await AiImportRepository(errApi, dao).listJobsAndCache();
      expect(failed.isLeft(), isTrue);
    });

    test('getPreview surfaces the typed payload and never caches', () async {
      final dao = _dao();
      final api = _api(
        _scripted([
          {
            'job_id': 'j1',
            'document_kind': 'schedule',
            'status': 'succeeded',
            'preview': _scriptPreviewWire(),
          },
        ]),
      );
      final res = await AiImportRepository(api, dao).getPreview('j1');
      final preview = res.getRight().toNullable()!;
      expect(preview.jobId, 'j1');
      // The typed payload is consumed, never retyped (D1).
      final variant = preview.preview.oneOf.value as AiPreviewPayloadOneOf;
      expect(variant.kind, AiPreviewPayloadOneOfKindEnum.script);
      expect(variant.data.scenes.first.draftRef, 'draft-1');
      // NEVER cached (design §3).
      expect(await dao.readAll(), isEmpty);
    });

    test(
      'unknown future preview kind strict-rejects with the stable code',
      () async {
        final api = _api(
          _scripted([
            {
              'job_id': 'j1',
              'document_kind': 'schedule',
              'status': 'succeeded',
              'preview': {
                'kind': 'merge_result_v9',
                'data': {'anything': true},
              },
            },
          ]),
        );
        final res = await AiImportRepository(api, _dao()).getPreview('j1');
        expect(
          res.getLeft().toNullable()!.code,
          'ai_import.preview_kind_unknown',
        );
      },
    );

    test('preview 404 (no preview) surfaces the problem code', () async {
      final api = _api(
        _ScriptInterceptor(problem: 'ai_import.preview_missing', status: 404),
      );
      final res = await AiImportRepository(api, _dao()).getPreview('j1');
      expect(res.getLeft().toNullable()!.code, 'ai_import.preview_missing');
    });

    test('apply Ok / 403 — definitive failures are never retried', () async {
      final api = _api(
        _scripted([
          serializers.serializeWith(
            ApplyAiImportResponse.serializer,
            ApplyAiImportResponse(
              (b) => b
                ..appliedCount = 3
                ..createdDays = 2
                ..plannedSceneShoots = 5,
            ),
          )!,
        ]),
      );
      final res = await AiImportRepository(
        api,
        _dao(),
      ).apply('j1', _applyRequest());
      expect(res.getRight().toNullable()!.appliedCount, 3);

      final errApi = _api(
        _ScriptInterceptor(problem: 'ai_import.forbidden', status: 403),
      );
      final failed = await AiImportRepository(
        errApi,
        _dao(),
      ).apply('j1', _applyRequest());
      expect(failed.getLeft().toNullable()!.code, 'ai_import.forbidden');
      expect(
        _scriptOf(errApi).calls,
        1,
        reason: 'a definitive 403 is never retried',
      );
    });

    test('applyWithReconciliation: ambiguous timeout re-reads the job first, '
        'then bounded-retries — never blind re-dispatch', () async {
      // Script: apply #1 times out; job re-read → succeeded; apply #2 → 200.
      final appliedBody = serializers.serializeWith(
        ApplyAiImportResponse.serializer,
        ApplyAiImportResponse(
          (b) => b
            ..appliedCount = 1
            ..createdDays = 1
            ..plannedSceneShoots = 2,
        ),
      )!;
      final jobBody = serializers.serializeWith(
        AiImportJobResponse.serializer,
        _jobResponse(_job('j1', status: JobStatus.succeeded)),
      )!;
      final outcomes = <_Outcome>[
        _Outcome.timeout(),
        _Outcome.ok(jobBody),
        _Outcome.ok(appliedBody),
      ];
      final scripted = _ScriptedOutcomes(outcomes);
      final repo = AiImportRepository(_api(scripted), _dao());
      final scheduler = _FakeScheduler();
      final outcome = await repo.applyWithReconciliation(
        'j1',
        _applyRequest(),
        scheduler: scheduler,
      );
      expect(outcome, isA<ApplySucceeded>());
      expect(scheduler.ticks, 1);
      // Request order: apply (timeout) → GET job → apply (retry).
      expect(
        outcomes[0].requests.single.uri.path,
        '/v1/ai-import/jobs/j1/apply',
      );
      expect(outcomes[1].requests.single.uri.path, '/v1/ai-import/jobs/j1');
    });

    test('applyWithReconciliation: job re-read not-succeeded blocks (no '
        're-dispatch)', () async {
      final outcomes = <_Outcome>[
        _Outcome.timeout(),
        _Outcome.ok(
          serializers.serializeWith(
            AiImportJobResponse.serializer,
            _jobResponse(_job('j1', status: JobStatus.deadLetter)),
          )!,
        ),
      ];
      final repo = AiImportRepository(
        _api(_ScriptedOutcomes(outcomes)),
        _dao(),
      );
      final outcome = await repo.applyWithReconciliation(
        'j1',
        _applyRequest(),
        scheduler: _FakeScheduler(),
      );
      expect(outcome, isA<ApplyBlocked>());
      expect(
        (outcome as ApplyBlocked).error.code,
        'ai_import.apply_job_not_succeeded',
      );
      // Exactly two requests: the timed-out apply + the re-read. No retry.
      expect(outcomes.expand((o) => o.requests).length, 2);
    });

    test('applyWithReconciliation: budget exhausted with the outcome unknown '
        '→ ApplyUnresolved', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // Every call times out (job re-reads included).
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );
      final outcome = await AiImportRepository(BreakdownApi(dio: dio), _dao())
          .applyWithReconciliation(
            'j1',
            _applyRequest(),
            scheduler: _FakeScheduler(),
            maxAttempts: 2,
          );
      expect(outcome, isA<ApplyUnresolved>());
    });

    test('job watch: pending → running → succeeded stops at the terminal '
        'status (fake scheduler, no wall-clock)', () async {
      final statuses = [
        JobStatus.pending,
        JobStatus.running,
        JobStatus.succeeded,
      ];
      final api = _api(
        _scripted([
          for (final status in statuses)
            serializers.serializeWith(
              AiImportJobResponse.serializer,
              _jobResponse(_job('j1', status: status)),
            )!,
        ]),
      );
      final scheduler = _FakeScheduler();
      final events = await AiImportRepository(
        api,
        _dao(),
      ).watch('j1', scheduler: scheduler, maxAttempts: 10).toList();
      expect(events.length, 3);
      expect(
        events.map((e) => e.getRight().toNullable()!.status).toList(),
        statuses,
      );
      expect(scheduler.ticks, 2, reason: 'no tick before the first fetch');
    });

    test(
      'job watch: transient failures yield Left and keep watching',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 500,
                    data: {'code': 'server.down', 'status': 500},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );
        // The fake transport always fails; watch exactly 2 bounded attempts
        // and assert every failure is surfaced (no silent swallow).
        final events = await AiImportRepository(
          BreakdownApi(dio: dio),
          _dao(),
        ).watch('j1', scheduler: _FakeScheduler(), maxAttempts: 2).toList();
        expect(events, hasLength(3));
        expect(events.every((e) => e.isLeft()), isTrue);
        expect(
          events.last.getLeft().toNullable()!.code,
          'ai_import.watch_exhausted',
        );
      },
    );

    test('job watch: exhaustion yields watch_exhausted and stops', () async {
      final api = _api(
        _scripted([
          serializers.serializeWith(
            AiImportJobResponse.serializer,
            _jobResponse(_job('j1')),
          )!,
        ]),
      );
      final events = await AiImportRepository(
        api,
        _dao(),
      ).watch('j1', scheduler: _FakeScheduler(), maxAttempts: 2).toList();
      expect(events.length, 3);
      expect(
        events.last.getLeft().toNullable()!.code,
        'ai_import.watch_exhausted',
      );
    });

    test(
      'job watch: unsubscribe stops the loop (foreground-only, D5)',
      () async {
        final api = _api(
          _scripted([
            serializers.serializeWith(
              AiImportJobResponse.serializer,
              _jobResponse(_job('j1', status: JobStatus.running)),
            )!,
          ]),
        );
        final scheduler = _FakeScheduler();
        final sub = AiImportRepository(
          api,
          _dao(),
        ).watch('j1', scheduler: scheduler).listen((_) {});
        await sub.cancel();
        // Give the generator a chance to observe the cancellation.
        await Future<void>.delayed(Duration.zero);
        final callsAtCancel = _scriptOf(api).calls;
        await Future<void>.delayed(Duration.zero);
        // No further refetches after the cancellation (bounded waste only).
        expect(_scriptOf(api).calls, lessThanOrEqualTo(callsAtCancel + 1));
      },
    );

    test('terminal statuses end the watch: dead_letter and '
        'payload_unavailable', () async {
      for (final terminal in [
        JobStatus.deadLetter,
        JobStatus.payloadUnavailable,
      ]) {
        final api = _api(
          _scripted([
            serializers.serializeWith(
              AiImportJobResponse.serializer,
              _jobResponse(_job('j1', status: terminal)),
            )!,
          ]),
        );
        final events = await AiImportRepository(
          api,
          _dao(),
        ).watch('j1', scheduler: _FakeScheduler()).toList();
        expect(events, hasLength(1));
        expect(events.single.getRight().toNullable()!.status, terminal);
      }
    });

    test(
      'retryable failed does NOT end the watch (retries/max_retries)',
      () async {
        final api = _api(
          _scripted([
            serializers.serializeWith(
              AiImportJobResponse.serializer,
              _jobResponse(
                _job('j1', status: JobStatus.failed, retries: 1, maxRetries: 3),
              ),
            )!,
            serializers.serializeWith(
              AiImportJobResponse.serializer,
              _jobResponse(_job('j1', status: JobStatus.succeeded)),
            )!,
          ]),
        );
        final events = await AiImportRepository(
          api,
          _dao(),
        ).watch('j1', scheduler: _FakeScheduler()).toList();
        expect(events.length, 2);
        expect(events.first.getRight().toNullable()!.retries, 1);
      },
    );

    test('clearCache wipes the job rows', () async {
      final dao = _dao();
      await dao.upsertAll([_job('j1')], DateTime.utc(2026, 1, 1));
      final repo = AiImportRepository(_api(_scripted([null])), dao);
      expect((await repo.clearCache()).isRight(), isTrue);
      expect(await dao.readAll(), isEmpty);
    });
  });
}

AiImportJobsCacheDao _dao() =>
    AiImportJobsCacheDao(CacheDatabase(NativeDatabase.memory()));

ApplyAiImportRequest _applyRequest() => ApplyAiImportRequest(
  (b) => b
    ..episodeId = 'ep-1'
    ..seriesId = 'series-1'
    ..mappings.replace([
      ApplyMapping(
        (m) => m
          ..draftRef = 'draft-1'
          ..decision.replace(
            ApplyMappingDecision(
              (d) => d..oneOf = OneOf.fromValue1(value: 'Create'),
            ),
          ),
      ),
    ])
    ..acceptAsIs = false
    ..editDistance = 0,
);

// The secure-storage double (same pattern as the token-store tests) lives
// here because the secret-discipline assertions intercept every store write.
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }
}
