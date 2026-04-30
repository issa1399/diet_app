// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authStateHash() => r'8a0cb8c25eb27745c00a0ad7ebb93f9b87c3f29d';

/// 現在のログインユーザーを返す Provider
/// ログアウト状態は null
///
/// Copied from [authState].
@ProviderFor(authState)
final authStateProvider = AutoDisposeStreamProvider<User?>.internal(
  authState,
  name: r'authStateProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$authStateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AuthStateRef = AutoDisposeStreamProviderRef<User?>;
String _$profileHash() => r'5dd245443a23bbf0fd7bd43ccb78868e9509a626';

/// 現在のユーザーの profile を取得する Provider
///
/// Copied from [profile].
@ProviderFor(profile)
final profileProvider = AutoDisposeFutureProvider<Profile?>.internal(
  profile,
  name: r'profileProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$profileHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ProfileRef = AutoDisposeFutureProviderRef<Profile?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
