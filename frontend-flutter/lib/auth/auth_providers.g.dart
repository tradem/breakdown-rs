// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The resolved per-flavor runtime configuration. Overridden at the
/// composition root (`bootstrap()` in `app.dart`) with the value built from
/// `--dart-define`; reading it before the override is a programming error.

@ProviderFor(appConfig)
final appConfigProvider = AppConfigProvider._();

/// The resolved per-flavor runtime configuration. Overridden at the
/// composition root (`bootstrap()` in `app.dart`) with the value built from
/// `--dart-define`; reading it before the override is a programming error.

final class AppConfigProvider
    extends $FunctionalProvider<AppConfig, AppConfig, AppConfig>
    with $Provider<AppConfig> {
  /// The resolved per-flavor runtime configuration. Overridden at the
  /// composition root (`bootstrap()` in `app.dart`) with the value built from
  /// `--dart-define`; reading it before the override is a programming error.
  AppConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appConfigHash();

  @$internal
  @override
  $ProviderElement<AppConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppConfig create(Ref ref) {
    return appConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppConfig>(value),
    );
  }
}

String _$appConfigHash() => r'fd823063416a416451d927a8a1c3cb547d488806';

/// The pinned-CA [Dio] for API traffic. Overridden at the composition root
/// with the client built by `buildApiClient` (fail-closed TLS, D4).

@ProviderFor(dio)
final dioProvider = DioProvider._();

/// The pinned-CA [Dio] for API traffic. Overridden at the composition root
/// with the client built by `buildApiClient` (fail-closed TLS, D4).

final class DioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  /// The pinned-CA [Dio] for API traffic. Overridden at the composition root
  /// with the client built by `buildApiClient` (fail-closed TLS, D4).
  DioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dioProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return dio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$dioHash() => r'dd72fdddff15a469157adb861429a67122414df2';

/// The [Dio] used for IdP (discovery/token) traffic: pinned by default,
/// plain-verifying only under the dev-flavor D1 exception.

@ProviderFor(idpDio)
final idpDioProvider = IdpDioProvider._();

/// The [Dio] used for IdP (discovery/token) traffic: pinned by default,
/// plain-verifying only under the dev-flavor D1 exception.

final class IdpDioProvider
    extends $FunctionalProvider<AsyncValue<Dio>, Dio, FutureOr<Dio>>
    with $FutureModifier<Dio>, $FutureProvider<Dio> {
  /// The [Dio] used for IdP (discovery/token) traffic: pinned by default,
  /// plain-verifying only under the dev-flavor D1 exception.
  IdpDioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'idpDioProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$idpDioHash();

  @$internal
  @override
  $FutureProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Dio> create(Ref ref) {
    return idpDio(ref);
  }
}

String _$idpDioHash() => r'43498f510daa7a07df695e16dc0fe5df69964b42';

/// Secure token persistence (`flutter_secure_storage` — never plaintext,
/// Task 2.1).

@ProviderFor(tokenStore)
final tokenStoreProvider = TokenStoreProvider._();

/// Secure token persistence (`flutter_secure_storage` — never plaintext,
/// Task 2.1).

final class TokenStoreProvider
    extends $FunctionalProvider<TokenStore, TokenStore, TokenStore>
    with $Provider<TokenStore> {
  /// Secure token persistence (`flutter_secure_storage` — never plaintext,
  /// Task 2.1).
  TokenStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tokenStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tokenStoreHash();

  @$internal
  @override
  $ProviderElement<TokenStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TokenStore create(Ref ref) {
    return tokenStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TokenStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TokenStore>(value),
    );
  }
}

String _$tokenStoreHash() => r'e1af499041ec8e3fd653ab4576cba8185f657d98';

/// OIDC client parameters from the environment (public PKCE client — no
/// secrets in the client tree, AGENTS.md §5).

@ProviderFor(oidcClientConfig)
final oidcClientConfigProvider = OidcClientConfigProvider._();

/// OIDC client parameters from the environment (public PKCE client — no
/// secrets in the client tree, AGENTS.md §5).

final class OidcClientConfigProvider
    extends
        $FunctionalProvider<
          OidcClientConfig,
          OidcClientConfig,
          OidcClientConfig
        >
    with $Provider<OidcClientConfig> {
  /// OIDC client parameters from the environment (public PKCE client — no
  /// secrets in the client tree, AGENTS.md §5).
  OidcClientConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'oidcClientConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$oidcClientConfigHash();

  @$internal
  @override
  $ProviderElement<OidcClientConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OidcClientConfig create(Ref ref) {
    return oidcClientConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OidcClientConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OidcClientConfig>(value),
    );
  }
}

String _$oidcClientConfigHash() => r'6e134cc359c8fcad704091ec80e8c4c00ebc4748';

/// Discovers the IdP's OIDC metadata over the IdP transport and validates the
/// issuer identity (Task 1.2, ADR-010/018). Fails closed as `AsyncError` when
/// discovery or the issuer check fails.

@ProviderFor(oidcClient)
final oidcClientProvider = OidcClientProvider._();

/// Discovers the IdP's OIDC metadata over the IdP transport and validates the
/// issuer identity (Task 1.2, ADR-010/018). Fails closed as `AsyncError` when
/// discovery or the issuer check fails.

final class OidcClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<OidcClient>>,
          Result<OidcClient>,
          FutureOr<Result<OidcClient>>
        >
    with
        $FutureModifier<Result<OidcClient>>,
        $FutureProvider<Result<OidcClient>> {
  /// Discovers the IdP's OIDC metadata over the IdP transport and validates the
  /// issuer identity (Task 1.2, ADR-010/018). Fails closed as `AsyncError` when
  /// discovery or the issuer check fails.
  OidcClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'oidcClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$oidcClientHash();

  @$internal
  @override
  $FutureProviderElement<Result<OidcClient>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<OidcClient>> create(Ref ref) {
    return oidcClient(ref);
  }
}

String _$oidcClientHash() => r'70adf11ca37b12e1f2bd1b7ae38a4998453376d8';

/// The platform browser/deep-link leg of the authorization flow. Overridden
/// at the composition root once the native Custom-Tabs wiring lands; tests
/// inject fakes.

@ProviderFor(authorizationUi)
final authorizationUiProvider = AuthorizationUiProvider._();

/// The platform browser/deep-link leg of the authorization flow. Overridden
/// at the composition root once the native Custom-Tabs wiring lands; tests
/// inject fakes.

final class AuthorizationUiProvider
    extends
        $FunctionalProvider<AuthorizationUi, AuthorizationUi, AuthorizationUi>
    with $Provider<AuthorizationUi> {
  /// The platform browser/deep-link leg of the authorization flow. Overridden
  /// at the composition root once the native Custom-Tabs wiring lands; tests
  /// inject fakes.
  AuthorizationUiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authorizationUiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authorizationUiHash();

  @$internal
  @override
  $ProviderElement<AuthorizationUi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthorizationUi create(Ref ref) {
    return authorizationUi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthorizationUi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthorizationUi>(value),
    );
  }
}

String _$authorizationUiHash() => r'acfcaf4e4cd55f317b1593ab7b6adb85163a5d6b';

/// The current auth session.
///
/// - Dev-auth mode (`DEV_AUTH_SUB`, no `OIDC_ISS` — backend ADR-018 D6
///   parity, Task 5.1): a permissive [AuthSession] with `DEV_AUTH_SUB` as
///   subject, no network, no tokens. Structurally unreachable in `prod`
///   (`AppConfig.devAuthMode` requires the dev flavor) and the composition
///   root aborts startup if prod ever carries the flag.
/// - Otherwise: the session is restored from secure storage; `null` means
///   signed out. Use [signIn]/[signOut] to mutate.

@ProviderFor(AuthSessionController)
final authSessionControllerProvider = AuthSessionControllerProvider._();

/// The current auth session.
///
/// - Dev-auth mode (`DEV_AUTH_SUB`, no `OIDC_ISS` — backend ADR-018 D6
///   parity, Task 5.1): a permissive [AuthSession] with `DEV_AUTH_SUB` as
///   subject, no network, no tokens. Structurally unreachable in `prod`
///   (`AppConfig.devAuthMode` requires the dev flavor) and the composition
///   root aborts startup if prod ever carries the flag.
/// - Otherwise: the session is restored from secure storage; `null` means
///   signed out. Use [signIn]/[signOut] to mutate.
final class AuthSessionControllerProvider
    extends $AsyncNotifierProvider<AuthSessionController, AuthSession?> {
  /// The current auth session.
  ///
  /// - Dev-auth mode (`DEV_AUTH_SUB`, no `OIDC_ISS` — backend ADR-018 D6
  ///   parity, Task 5.1): a permissive [AuthSession] with `DEV_AUTH_SUB` as
  ///   subject, no network, no tokens. Structurally unreachable in `prod`
  ///   (`AppConfig.devAuthMode` requires the dev flavor) and the composition
  ///   root aborts startup if prod ever carries the flag.
  /// - Otherwise: the session is restored from secure storage; `null` means
  ///   signed out. Use [signIn]/[signOut] to mutate.
  AuthSessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authSessionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authSessionControllerHash();

  @$internal
  @override
  AuthSessionController create() => AuthSessionController();
}

String _$authSessionControllerHash() =>
    r'66d7dc7175ba8681a1a8398b7c201ad7f628f035';

/// The current auth session.
///
/// - Dev-auth mode (`DEV_AUTH_SUB`, no `OIDC_ISS` — backend ADR-018 D6
///   parity, Task 5.1): a permissive [AuthSession] with `DEV_AUTH_SUB` as
///   subject, no network, no tokens. Structurally unreachable in `prod`
///   (`AppConfig.devAuthMode` requires the dev flavor) and the composition
///   root aborts startup if prod ever carries the flag.
/// - Otherwise: the session is restored from secure storage; `null` means
///   signed out. Use [signIn]/[signOut] to mutate.

abstract class _$AuthSessionController extends $AsyncNotifier<AuthSession?> {
  FutureOr<AuthSession?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AuthSession?>, AuthSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AuthSession?>, AuthSession?>,
              AsyncValue<AuthSession?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
