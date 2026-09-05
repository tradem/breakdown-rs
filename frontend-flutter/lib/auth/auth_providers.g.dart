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

/// The platform browser/deep-link leg of the authorization flow.
///
/// Resolves to [PlatformAuthorizationUi] (Custom Tabs + `app_links`
/// redirect capture, spec `flutter-auth-shell`) whenever the build carries
/// a routable `OIDC_REDIRECT_URI`; otherwise the fail-closed
/// [NotConfiguredAuthorizationUi] — without a redirect the platform leg
/// could never return, so no authorization request may start. Tests inject
/// fakes via overrides.

@ProviderFor(authorizationUi)
final authorizationUiProvider = AuthorizationUiProvider._();

/// The platform browser/deep-link leg of the authorization flow.
///
/// Resolves to [PlatformAuthorizationUi] (Custom Tabs + `app_links`
/// redirect capture, spec `flutter-auth-shell`) whenever the build carries
/// a routable `OIDC_REDIRECT_URI`; otherwise the fail-closed
/// [NotConfiguredAuthorizationUi] — without a redirect the platform leg
/// could never return, so no authorization request may start. Tests inject
/// fakes via overrides.

final class AuthorizationUiProvider
    extends
        $FunctionalProvider<AuthorizationUi, AuthorizationUi, AuthorizationUi>
    with $Provider<AuthorizationUi> {
  /// The platform browser/deep-link leg of the authorization flow.
  ///
  /// Resolves to [PlatformAuthorizationUi] (Custom Tabs + `app_links`
  /// redirect capture, spec `flutter-auth-shell`) whenever the build carries
  /// a routable `OIDC_REDIRECT_URI`; otherwise the fail-closed
  /// [NotConfiguredAuthorizationUi] — without a redirect the platform leg
  /// could never return, so no authorization request may start. Tests inject
  /// fakes via overrides.
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

String _$authorizationUiHash() => r'3cd40fcb27a1f5629fe03ce7e9592f9b9a617216';

@ProviderFor(AuthSessionController)
final authSessionControllerProvider = AuthSessionControllerProvider._();

final class AuthSessionControllerProvider
    extends $AsyncNotifierProvider<AuthSessionController, AuthSession?> {
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
    r'46c422b68ddfc2469fa5e36108a405c9ba5c95fb';

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
