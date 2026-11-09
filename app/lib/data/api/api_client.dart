import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/sync_state.dart';
import 'dto.dart';

/// Failure talking to the bar-tab server. Messages are short and never
/// contain the device key.
sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server rejected the device key (HTTP 401).
final class UnauthorisedException extends ApiException {
  const UnauthorisedException() : super('Device key rejected');
}

/// The admin session is gone (expired, revoked, server restarted): HTTP 401
/// `admin_session_required`.
final class AdminSessionEndedException extends ApiException {
  const AdminSessionEndedException() : super('Admin session ended');
}

/// A storno was refused: 404 `booking_not_found` or 409 `period_closed` /
/// `already_cancelled`. [reason] is the server's `detail`.
final class BookingNotCancellableException extends ApiException {
  BookingNotCancellableException(this.reason)
    : super('Booking not cancellable: $reason');
  final String reason;
}

/// An admin write was refused: 404, 409 or 422. [detail] is the server's
/// `detail` string, `"unknown"` when the body has none (FastAPI's own
/// validation errors carry a list).
final class RejectedException extends ApiException {
  RejectedException(this.detail) : super('Rejected: $detail');
  final String detail;
}

/// Closing a settlement was refused: 409 `stale_review`, the data changed since
/// the review. Review again.
final class StaleReviewException extends ApiException {
  const StaleReviewException() : super('Settlement review is stale');
}

/// Closing a settlement was refused: 409 `already_settled`.
final class AlreadySettledException extends ApiException {
  const AlreadySettledException() : super('Period already settled');
}

/// 422 `invalid_email`: a recipient address is malformed.
final class InvalidEmailException extends ApiException {
  const InvalidEmailException() : super('Invalid email address');
}

/// The server could not be reached (socket, TLS, timeout).
final class NetworkException extends ApiException {
  const NetworkException(super.message);
}

/// HTTP 5xx or an unexpected 4xx.
final class ServerException extends ApiException {
  ServerException(this.status) : super('Server answered HTTP $status');
  final int status;
}

/// The response body was not what the contract promises.
final class ContractException extends ApiException {
  const ContractException(super.message);
}

sealed class CatalogFetch {
  const CatalogFetch();
}

final class CatalogUnchanged extends CatalogFetch {
  const CatalogUnchanged();
}

final class CatalogUpdated extends CatalogFetch {
  const CatalogUpdated(this.catalog);
  final CatalogDto catalog;
}

sealed class AdminLogin {
  const AdminLogin();
}

final class AdminLoggedIn extends AdminLogin {
  const AdminLoggedIn(this.token);
  final String token;
}

final class AdminWrongPin extends AdminLogin {
  const AdminWrongPin();
}

final class AdminLockedOut extends AdminLogin {
  const AdminLockedOut(this.retryAfter);
  final int retryAfter;
}

sealed class PinChange {
  const PinChange();
}

final class PinChanged extends PinChange {
  const PinChanged();
}

final class PinWrong extends PinChange {
  const PinWrong();
}

final class PinLocked extends PinChange {
  const PinLocked(this.retryAfter);
  final int retryAfter;
}

/// How long a settlement close may take: the server mails the PDF before it
/// answers, with an SMTP timeout above the default request timeout.
const kCloseSettlementTimeout = Duration(seconds: 60);

class BarTabApi {
  BarTabApi({
    required this._client,
    required this._config,
    this._timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final ServerConfig _config;
  final Duration _timeout;

  Future<CatalogFetch> getCatalog({String? etag}) async {
    final response = await _send(
      'GET',
      'catalog',
      headers: {if (etag != null) 'If-None-Match': '"$etag"'},
    );
    if (response.statusCode == 304) return const CatalogUnchanged();
    _checkStatus(response);
    return CatalogUpdated(_parse(response, CatalogDto.fromJson));
  }

  Future<List<BookingResultDto>> postBookings(
    List<BookingInDto> bookings,
  ) async {
    final response = await _send(
      'POST',
      'bookings',
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: utf8.encode(
        jsonEncode(BookingBatchRequestDto(bookings: bookings).toJson()),
      ),
    );
    _checkStatus(response);
    return _parse(response, BookingBatchResponseDto.fromJson).results;
  }

  Future<TabsDto> getTabs() async {
    final response = await _send('GET', 'tabs');
    _checkStatus(response);
    return _parse(response, TabsDto.fromJson);
  }

  Future<RankingsDto> getRankings() async {
    final response = await _send('GET', 'rankings');
    _checkStatus(response);
    return _parse(response, RankingsDto.fromJson);
  }

  Future<AdminLogin> openAdminSession(String pin) async {
    final response = await _send(
      'POST',
      'admin/session',
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: utf8.encode(jsonEncode(AdminSessionRequestDto(pin: pin).toJson())),
    );
    if (response.statusCode == 401 && _detail(response) == 'wrong_pin') {
      return const AdminWrongPin();
    }
    if (response.statusCode == 429) {
      return AdminLockedOut(_parse(response, LockedDto.fromJson).retryAfter);
    }
    _checkStatus(response);
    return AdminLoggedIn(
      _parse(response, AdminSessionResponseDto.fromJson).token,
    );
  }

  Future<void> closeAdminSession(String token) async {
    _checkStatus(await _send('DELETE', 'admin/session', admin: token));
  }

  Future<void> pingAdmin(String token) async {
    _checkStatus(await _send('GET', 'admin/ping', admin: token));
  }

  Future<List<AdminBookingDto>> listAdminBookings(
    String token, {
    String? personId,
  }) async {
    final response = await _send(
      'GET',
      'admin/bookings',
      query: {'person_id': ?personId},
      admin: token,
    );
    _checkStatus(response);
    return _parse(response, AdminBookingsDto.fromJson).bookings;
  }

  Future<AdminBookingDto> cancelBooking(String token, String bookingId) async {
    final response = await _send(
      'POST',
      'admin/bookings/${Uri.encodeComponent(bookingId)}/cancel',
      admin: token,
    );
    final status = response.statusCode;
    if (status == 404 || status == 409) {
      throw BookingNotCancellableException(_detail(response) ?? 'unknown');
    }
    _checkStatus(response);
    return _parse(response, AdminBookingDto.fromJson);
  }

  Future<PersonDto> createPerson(String token, PersonWriteDto body) =>
      _write('POST', 'admin/persons', token, body.toJson(), PersonDto.fromJson);

  Future<PersonDto> updatePerson(
    String token,
    String id,
    PersonWriteDto body,
  ) => _write(
    'PUT',
    'admin/persons/${Uri.encodeComponent(id)}',
    token,
    body.toJson(),
    PersonDto.fromJson,
  );

  Future<DrinkDto> createDrink(String token, DrinkWriteDto body) =>
      _write('POST', 'admin/drinks', token, body.toJson(), DrinkDto.fromJson);

  Future<DrinkDto> updateDrink(String token, String id, DrinkWriteDto body) =>
      _write(
        'PUT',
        'admin/drinks/${Uri.encodeComponent(id)}',
        token,
        body.toJson(),
        DrinkDto.fromJson,
      );

  Future<GroupDto> createGroup(String token, GroupWriteDto body) =>
      _write('POST', 'admin/groups', token, body.toJson(), GroupDto.fromJson);

  Future<GroupDto> updateGroup(String token, String id, GroupWriteDto body) =>
      _write(
        'PUT',
        'admin/groups/${Uri.encodeComponent(id)}',
        token,
        body.toJson(),
        GroupDto.fromJson,
      );

  Future<void> deleteGroup(String token, String id) => _writeNoContent(
    'DELETE',
    'admin/groups/${Uri.encodeComponent(id)}',
    token,
  );

  Future<PriceTierDto> createPriceTier(String token, String name) => _write(
    'POST',
    'admin/price-tiers',
    token,
    TierWriteDto(name: name).toJson(),
    PriceTierDto.fromJson,
  );

  Future<PriceTierDto> updatePriceTier(String token, String id, String name) =>
      _write(
        'PUT',
        'admin/price-tiers/${Uri.encodeComponent(id)}',
        token,
        TierWriteDto(name: name).toJson(),
        PriceTierDto.fromJson,
      );

  Future<void> deletePriceTier(String token, String id) => _writeNoContent(
    'DELETE',
    'admin/price-tiers/${Uri.encodeComponent(id)}',
    token,
  );

  Future<void> reorderGroups(String token, List<String> ids) => _writeNoContent(
    'PUT',
    'admin/order/groups',
    token,
    OrderWriteDto(ids: ids).toJson(),
  );

  Future<void> reorderPriceTiers(String token, List<String> ids) =>
      _writeNoContent(
        'PUT',
        'admin/order/price-tiers',
        token,
        OrderWriteDto(ids: ids).toJson(),
      );

  Future<void> reorderDrinks(String token, String groupId, List<String> ids) =>
      _writeNoContent(
        'PUT',
        'admin/order/drinks/${Uri.encodeComponent(groupId)}',
        token,
        OrderWriteDto(ids: ids).toJson(),
      );

  Future<List<DeliveryDto>> createDeliveries(
    String token,
    List<DeliveryInDto> items,
  ) async => (await _write(
    'POST',
    'admin/deliveries',
    token,
    DeliveryBatchRequestDto(deliveries: items).toJson(),
    DeliveriesDto.fromJson,
  )).deliveries;

  Future<List<DeliveryDto>> listDeliveries(String token) async {
    final response = await _send('GET', 'admin/deliveries', admin: token);
    _checkStatus(response);
    return _parse(response, DeliveriesDto.fromJson).deliveries;
  }

  Future<DeliveryDto> cancelDelivery(String token, String id) => _write(
    'POST',
    'admin/deliveries/${Uri.encodeComponent(id)}/cancel',
    token,
    null,
    DeliveryDto.fromJson,
  );

  Future<PinChange> changeAdminPin(
    String token,
    String current,
    String next,
  ) async {
    final response = await _send(
      'PUT',
      'admin/pin',
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: utf8.encode(
        jsonEncode(
          PinChangeRequestDto(currentPin: current, newPin: next).toJson(),
        ),
      ),
      admin: token,
    );
    if (response.statusCode == 403 && _detail(response) == 'wrong_pin') {
      return const PinWrong();
    }
    if (response.statusCode == 429) {
      return PinLocked(_parse(response, LockedDto.fromJson).retryAfter);
    }
    _checkStatus(response);
    return const PinChanged();
  }

  Future<StockDto> getStock(String token) async {
    final response = await _send('GET', 'admin/stock', admin: token);
    _checkStatus(response);
    return _parse(response, StockDto.fromJson);
  }

  Future<SettlementReviewDto> reviewSettlement(
    String token,
    Map<String, int> counts,
  ) => _write(
    'POST',
    'admin/settlement/review',
    token,
    _counts(counts).toJson(),
    SettlementReviewDto.fromJson,
  );

  /// Closes the period. 201 (first close) and 200 (replay) both succeed.
  /// Waits up to [timeout] instead of the client's request timeout.
  Future<SettlementCloseDto> closeSettlement(
    String token,
    String reviewToken,
    Map<String, int> counts, {
    Duration timeout = kCloseSettlementTimeout,
  }) => _write(
    'POST',
    'admin/settlement/close',
    token,
    CloseRequestDto(
      token: reviewToken,
      counts: _counts(counts).counts,
    ).toJson(),
    SettlementCloseDto.fromJson,
    timeout: timeout,
  );

  Future<void> recordOpeningCount(String token, Map<String, int> counts) =>
      _writeNoContent(
        'POST',
        'admin/opening-count',
        token,
        _counts(counts).toJson(),
      );

  Future<SettingsDto> getSettings(String token) async {
    final response = await _send('GET', 'admin/settings', admin: token);
    _checkStatus(response);
    return _parse(response, SettingsDto.fromJson);
  }

  Future<void> setRecipients(String token, List<String> recipients) =>
      _writeNoContent(
        'PUT',
        'admin/settings/recipients',
        token,
        RecipientsWriteDto(recipients: recipients).toJson(),
      );

  Future<void> setValuationTier(String token, String tierId) => _writeNoContent(
    'PUT',
    'admin/settings/valuation-tier',
    token,
    ValuationTierWriteDto(tierId: tierId).toJson(),
  );

  /// Re-sends the last settlement; the server mails before it answers, so
  /// this waits as long as [closeSettlement].
  Future<MailStatus> resendSettlement(String token) async => (await _write(
    'POST',
    'admin/settlement/resend',
    token,
    null,
    ResendDto.fromJson,
    timeout: kCloseSettlementTimeout,
  )).mailStatus;

  CountsRequestDto _counts(Map<String, int> counts) => CountsRequestDto(
    counts: [
      for (final e in counts.entries)
        CountInDto(drinkId: e.key, quantity: e.value),
    ],
  );

  /// An admin write with an optional JSON [json] body and a parsed answer.
  Future<T> _write<T>(
    String method,
    String path,
    String token,
    Map<String, dynamic>? json,
    T Function(Map<String, dynamic>) from, {
    Duration? timeout,
  }) async {
    final response = await _sendWrite(
      method,
      path,
      token,
      json,
      timeout: timeout,
    );
    return _parse(response, from);
  }

  /// An admin write answered with 204.
  Future<void> _writeNoContent(
    String method,
    String path,
    String token, [
    Map<String, dynamic>? json,
  ]) async {
    await _sendWrite(method, path, token, json);
  }

  /// Sends an admin write; 404, 409 and 422 become [RejectedException] (or a
  /// specific exception for the settlement and settings codes).
  Future<http.Response> _sendWrite(
    String method,
    String path,
    String token,
    Map<String, dynamic>? json, {
    Duration? timeout,
  }) async {
    final response = await _send(
      method,
      path,
      timeout: timeout,
      headers: json == null
          ? const {}
          : {'Content-Type': 'application/json; charset=utf-8'},
      body: json == null ? null : utf8.encode(jsonEncode(json)),
      admin: token,
    );
    final status = response.statusCode;
    if (status == 404 || status == 409 || status == 422) {
      final detail = _detail(response);
      if (status == 409 && detail == 'stale_review') {
        throw const StaleReviewException();
      }
      if (status == 409 && detail == 'already_settled') {
        throw const AlreadySettledException();
      }
      if (status == 422 && detail == 'invalid_email') {
        throw const InvalidEmailException();
      }
      throw RejectedException(detail ?? 'unknown');
    }
    _checkStatus(response);
    return response;
  }

  Uri _uri(String path, [Map<String, String> query = const {}]) {
    final base = _config.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/$path');
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  /// The JSON `detail` of an error response, or `null` if unreadable.
  String? _detail(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final detail = (json as Map<String, dynamic>)['detail'];
      return detail is String ? detail : null;
    } on Object {
      return null;
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
    Map<String, String> query = const {},
    String? admin,
    Duration? timeout,
  }) async {
    final limit = timeout ?? _timeout;
    final request = http.Request(method, _uri(path, query))
      ..headers['Authorization'] = 'Bearer ${_config.deviceKey}'
      ..headers.addAll({'X-Admin-Token': ?admin})
      ..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(limit),
      ).timeout(limit);
    } on TimeoutException {
      throw const NetworkException('Request timed out');
    } on SocketException {
      throw const NetworkException('Connection failed');
    } on HandshakeException {
      throw const NetworkException('TLS handshake failed');
    } on http.ClientException {
      throw const NetworkException('Connection failed');
    }
  }

  void _checkStatus(http.Response response) {
    final status = response.statusCode;
    if (status == 401) {
      if (_detail(response) == 'admin_session_required') {
        throw const AdminSessionEndedException();
      }
      throw const UnauthorisedException();
    }
    if (status < 200 || status >= 300) throw ServerException(status);
  }

  T _parse<T>(http.Response response, T Function(Map<String, dynamic>) from) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return from(json as Map<String, dynamic>);
    } on Object {
      throw const ContractException('Unexpected response body');
    }
  }
}
