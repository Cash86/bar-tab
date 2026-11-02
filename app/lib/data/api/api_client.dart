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

  Uri _uri(String path) {
    final base = _config.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/api/v1/$path');
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, _uri(path))
      ..headers['Authorization'] = 'Bearer ${_config.deviceKey}'
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
    if (status == 401) throw const UnauthorisedException();
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
