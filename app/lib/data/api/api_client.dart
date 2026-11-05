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
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers['Authorization'] = 'Bearer ${_config.deviceKey}'
      ..headers.addAll({'X-Admin-Token': ?admin})
      ..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
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
