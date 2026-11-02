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

@freezed
abstract class ServerConfig with _$ServerConfig {
  const factory ServerConfig({
    required String baseUrl,
    required String deviceKey,
  }) = _ServerConfig;
}
