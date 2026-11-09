import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_state.freezed.dart';

@freezed
abstract class SyncCounts with _$SyncCounts {
  /// [failed] is rejected plus conflict bookings.
  const factory SyncCounts({required int queued, required int failed}) =
      _SyncCounts;
}

@freezed
abstract class SyncState with _$SyncState {
  const factory SyncState({
    required int queued,
    required int failed,
    required bool isUnauthorised,
    required bool isOffline,
    DateTime? lastSuccessAt,
  }) = _SyncState;
}

/// Outcome of the flush before a settlement. A settlement may start only if
/// [reachable] and [pending] is 0.
@freezed
abstract class FlushResult with _$FlushResult {
  /// [reachable]: the server answered during this flush (unauthorised counts
  /// as not reachable). [pending]: bookings still queued, held or not.
  /// [failed]: rejected plus conflict bookings.
  const factory FlushResult({
    required bool reachable,
    required int pending,
    required int failed,
  }) = _FlushResult;
}

@freezed
abstract class ServerConfig with _$ServerConfig {
  const factory ServerConfig({
    required String baseUrl,
    required String deviceKey,
  }) = _ServerConfig;
}
