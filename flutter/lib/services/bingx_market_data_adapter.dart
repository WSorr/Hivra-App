import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../models/external_effect_models.dart';

/// Normalized BingX evidence and explicitly authorized effects. Strategy and
/// lifecycle decisions belong to the installed WASM package.
class BingxMarketDataAdapter implements ExternalEffectAdapter {
  final Future<String> Function(Uri)? _read;
  final Future<String> Function(Uri, Map<String, String>)? _readAuthenticated;
  final DateTime Function() _clock;
  final Future<Map<String, String>> Function(ExternalEffectAdapterRequest)?
  _credentials;
  final Future<void> Function(Map<String, dynamic>)? _authorize;
  final Future<String> Function(String, Uri, Map<String, String>)?
  _sendAuthenticated;
  DateTime? _lastRequest;

  BingxMarketDataAdapter({
    Future<String> Function(Uri)? read,
    Future<String> Function(Uri, Map<String, String>)? readAuthenticated,
    DateTime Function()? clock,
    Future<String> Function(String, Uri, Map<String, String>)?
    sendAuthenticated,
    Future<Map<String, String>> Function(ExternalEffectAdapterRequest)?
    credentials,
    Future<void> Function(Map<String, dynamic>)? authorize,
  }) : _read = read,
       _readAuthenticated = readAuthenticated,
       _clock = clock ?? DateTime.now,
       _sendAuthenticated = sendAuthenticated,
       _credentials = credentials,
       _authorize = authorize;

  BingxMarketDataAdapter scopedEffects({
    required Future<Map<String, String>> Function(ExternalEffectAdapterRequest)
    credentials,
    required Future<void> Function(Map<String, dynamic>) authorize,
  }) => BingxMarketDataAdapter(
    read: _read,
    readAuthenticated: _readAuthenticated,
    sendAuthenticated: _sendAuthenticated,
    clock: _clock,
    credentials: credentials,
    authorize: authorize,
  );

  static String entryOperationId(Map<String, dynamic> plan) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode([
                plan['account_id'],
                plan['symbol'],
                plan['side'],
                plan['timeframe'],
                plan['origin'],
                plan['first_known'],
                plan['line_price'],
                plan['price'],
                plan['quantity'],
                plan['stop_price'],
                plan['margin'],
                plan['leverage'],
                plan['prepared_at_ms'],
                plan['expires_at_ms'],
              ]),
            ),
          )
          .toString();

  static String cancelOperationId(Map<String, dynamic> plan, String orderId) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'order.entry.cancel',
                entryOperationId(plan),
                orderId,
              ]),
            ),
          )
          .toString();

  static String exitOperationId(Map<String, dynamic> plan) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'position.exit.place',
                entryOperationId(
                  Map<String, dynamic>.from(plan['entry_plan'] as Map),
                ),
                plan['position_id'],
                plan['quantity'],
                plan['average_price'],
                plan['price'],
                plan['prepared_at_ms'],
                plan['expires_at_ms'],
              ]),
            ),
          )
          .toString();

  Map<String, dynamic> _exitPlan(ExternalEffectAdapterRequest request) {
    request.validate();
    final raw = jsonDecode(request.canonicalPayloadJson);
    if (request.providerId != 'bingx' ||
        request.effectKind != 'position.exit.place' ||
        raw is! Map ||
        raw.length != 7 ||
        raw['entry_plan'] is! Map ||
        sha256.convert(utf8.encode(request.canonicalPayloadJson)).toString() !=
            request.payloadHashHex) {
      throw const FormatException('Invalid position exit contract');
    }
    final p = Map<String, dynamic>.from(raw);
    final entry = _entryPlan(_exitEntry(request, p));
    if (request.operationId != exitOperationId(p) ||
        p['position_id'] is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(p['position_id']) ||
        [
          'quantity',
          'average_price',
          'price',
        ].any((k) => p[k] is! num || !p[k].isFinite || p[k] <= 0) ||
        p['quantity'] > entry['quantity'] ||
        p['prepared_at_ms'] is! int ||
        p['expires_at_ms'] is! int ||
        p['prepared_at_ms'] < entry['prepared_at_ms'] ||
        p['expires_at_ms'] <= p['prepared_at_ms'] ||
        p['expires_at_ms'] - p['prepared_at_ms'] > 60000 ||
        (entry['side'] == 'long'
            ? p['price'] <= p['average_price']
            : p['price'] >= p['average_price'])) {
      throw const FormatException('Invalid bounded reducing limit exit');
    }
    return p;
  }

  ExternalEffectAdapterRequest _exitEntry(
    ExternalEffectAdapterRequest request,
    Map<String, dynamic> p,
  ) {
    final entry = Map<String, dynamic>.from(p['entry_plan'] as Map);
    final canonical = jsonEncode(entry);
    return ExternalEffectAdapterRequest(
      ownerCapsuleHex: request.ownerCapsuleHex,
      operationId: entryOperationId(entry),
      pluginId: request.pluginId,
      providerId: 'bingx',
      accountBindingId: request.accountBindingId,
      effectKind: 'order.entry.place',
      canonicalPayloadJson: canonical,
      payloadHashHex: sha256.convert(utf8.encode(canonical)).toString(),
    );
  }

  Future<Map<String, dynamic>> readExit(
    ExternalEffectAdapterRequest request,
  ) async {
    final p = _exitPlan(request);
    final entry = p['entry_plan'] as Map;
    final credentials = await _boundCredentials(request);
    final client = request.operationId.substring(0, 40);
    final data = await _signed('GET', '/openApi/swap/v2/trade/order', {
      'symbol': entry['symbol'],
      'clientOrderId': client,
    }, credentials);
    final row =
        data is Map && data['order'] is Map ? data['order'] as Map : data;
    final id =
        row is Map ? (row['orderID'] ?? row['orderId'])?.toString() : null;
    final side = entry['side'] == 'long' ? 'SELL' : 'BUY';
    final positionSide = entry['side'] == 'long' ? 'LONG' : 'SHORT';
    final qty = row is Map ? num.tryParse(row['origQty'].toString()) : null;
    final filled =
        row is Map ? num.tryParse(row['executedQty'].toString()) : null;
    final avg = row is Map ? num.tryParse(row['avgPrice'].toString()) : null;
    final status =
        row is Map
            ? const {
              'NEW': 'open',
              'PENDING': 'open',
              'PARTIALLY_FILLED': 'partial',
              'FILLED': 'filled',
              'CANCELED': 'cancelled',
              'CANCELLED': 'cancelled',
              'REJECTED': 'rejected',
              'EXPIRED': 'expired',
            }[row['status']]
            : null;
    if (row is! Map ||
        id == null ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(id) ||
        (request.providerReferenceId != null &&
            id != request.providerReferenceId) ||
        row['symbol'] != entry['symbol'] ||
        row['clientOrderId'] != client ||
        row['side'] != side ||
        !['BOTH', positionSide].contains(row['positionSide']) ||
        (row['positionSide'] == 'BOTH' &&
            ![true, 'true'].contains(row['reduceOnly'])) ||
        row['type'] != 'LIMIT' ||
        qty != p['quantity'] ||
        num.tryParse(row['price'].toString()) != p['price'] ||
        status == null ||
        filled == null ||
        !filled.isFinite ||
        filled < 0 ||
        filled > qty! ||
        avg == null ||
        !avg.isFinite ||
        avg < 0 ||
        (filled > 0 && avg <= 0) ||
        (status == 'filled' && filled != qty) ||
        (status == 'partial' && (filled == 0 || filled == qty))) {
      throw const FormatException(
        'Exact reducing exit evidence does not match',
      );
    }
    return {
      'account_id': request.accountBindingId,
      'symbol': entry['symbol'],
      'client_order_id': client,
      'order_id': id,
      'status': status,
      'filled_quantity': filled,
      'average_price': avg,
      'observed_at_ms': _clock().toUtc().millisecondsSinceEpoch,
    };
  }

  Future<ExternalEffectAdapterResult> _placeExit(
    ExternalEffectAdapterRequest request,
  ) async {
    final p = _exitPlan(request);
    final entry = p['entry_plan'] as Map;
    late Map<String, String> credentials;
    late bool hedge;
    try {
      credentials = await _boundCredentials(request);
      final fill = await readEntry(_exitEntry(request, p));
      final positions = await _readPositions(entry['symbol'], credentials);
      if (positions.length != 1 ||
          fill['filled_quantity'] < p['quantity'] ||
          positions.single['position_id'] != p['position_id'] ||
          positions.single['side'] != entry['side'] ||
          positions.single['quantity'] != p['quantity'] ||
          (positions.single['average_price'] - p['average_price']).abs() >
              p['average_price'] * 1e-9 ||
          (fill['average_price'] - p['average_price']).abs() >
              p['average_price'] * 1e-9) {
        throw StateError('Position changed or is not the journaled fill');
      }
      final mode = await _signed(
        'GET',
        '/openApi/swap/v1/positionSide/dual',
        {},
        credentials,
      );
      final value = mode is Map ? mode['dualSidePosition'] : null;
      if (![true, false, 'true', 'false'].contains(value)) {
        throw const FormatException('Unknown position mode');
      }
      hedge = value == true || value == 'true';
      if (_authorize == null) throw StateError('Exit is not authorized');
      await _authorize(p);
      final now = _clock().millisecondsSinceEpoch;
      if (now < p['prepared_at_ms'] || now > p['expires_at_ms']) {
        throw StateError('Exit plan expired');
      }
    } catch (_) {
      return const ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'exit_not_sent',
        errorMessage: 'No exit sent: refresh the exact position and authority',
      );
    }
    try {
      await _signed('POST', '/openApi/swap/v2/trade/order', {
        'symbol': entry['symbol'],
        'side': entry['side'] == 'long' ? 'SELL' : 'BUY',
        'positionSide':
            hedge ? (entry['side'] == 'long' ? 'LONG' : 'SHORT') : 'BOTH',
        if (!hedge) 'reduceOnly': 'true',
        'positionId': p['position_id'],
        'type': 'LIMIT',
        'timeInForce': 'GTC',
        'quantity': p['quantity'].toString(),
        'price': p['price'].toString(),
        'clientOrderId': request.operationId.substring(0, 40),
      }, credentials);
    } on _BingxRejected catch (e) {
      if (e.code > 0 && e.code != 101481) {
        return ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.terminalFailure,
          errorCode: 'provider_rejected',
          errorMessage: 'BingX rejected exit (code ${e.code})',
        );
      }
    } catch (_) {
      // A timeout is not permission to retry POST. Reconcile this client ID.
    }
    return reconcile(request);
  }

  ExternalEffectAdapterRequest _entryForCancellation(
    ExternalEffectAdapterRequest request,
  ) {
    request.validate();
    final payload = jsonDecode(request.canonicalPayloadJson);
    if (request.providerId != 'bingx' ||
        request.effectKind != 'order.entry.cancel' ||
        sha256.convert(utf8.encode(request.canonicalPayloadJson)).toString() !=
            request.payloadHashHex ||
        payload is! Map ||
        payload.length != 2 ||
        payload['plan'] is! Map ||
        payload['order_id'] is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(payload['order_id'])) {
      throw const FormatException('Invalid exact entry cancellation');
    }
    final plan = Map<String, dynamic>.from(payload['plan'] as Map);
    if (request.operationId != cancelOperationId(plan, payload['order_id'])) {
      throw const FormatException('Cancellation identity changed');
    }
    final canonical = jsonEncode(plan);
    final entry = ExternalEffectAdapterRequest(
      ownerCapsuleHex: request.ownerCapsuleHex,
      operationId: entryOperationId(plan),
      pluginId: request.pluginId,
      providerId: request.providerId,
      accountBindingId: request.accountBindingId,
      effectKind: 'order.entry.place',
      canonicalPayloadJson: canonical,
      payloadHashHex: sha256.convert(utf8.encode(canonical)).toString(),
      providerReferenceId: payload['order_id'],
    );
    _entryPlan(entry);
    return entry;
  }

  Future<dynamic> _signed(
    String method,
    String path,
    Map<String, String> params,
    Map<String, String> credentials,
  ) async {
    final key = credentials['api_key'] ?? '';
    final secret = credentials['secret_key'] ?? '';
    if ([key, secret].any(
      (s) =>
          s.isEmpty ||
          s.length > 512 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s),
    )) {
      throw const FormatException('Reconnect your BingX account');
    }
    final query = <String, String>{
      ...params,
      'recvWindow': '5000',
      'timestamp': _clock().toUtc().millisecondsSinceEpoch.toString(),
    };
    final names = query.keys.toList()..sort();
    final canonical = names.map((k) => '$k=${query[k]}').join('&');
    final uri = Uri.https('open-api.bingx.com', path, {
      for (final name in names) name: query[name]!,
      'signature':
          Hmac(
            sha256,
            utf8.encode(secret),
          ).convert(utf8.encode(canonical)).toString(),
    });
    final headers = {'X-BX-APIKEY': key, 'X-SOURCE-KEY': 'BX-AI-SKILL'};
    dynamic decoded;
    try {
      final raw =
          _sendAuthenticated != null
              ? await _sendAuthenticated(method, uri, headers)
              : method == 'GET' && _readAuthenticated != null
              ? await _readAuthenticated(uri, headers)
              : await _httpRead(uri, headers: headers, method: method);
      if (utf8.encode(raw).length > 512 * 1024) throw const FormatException();
      decoded = jsonDecode(raw);
    } catch (_) {
      throw StateError(
        method == 'GET'
            ? 'BingX read unavailable; no current observation. Try again.'
            : 'BingX request unavailable; outcome may be unknown. Refresh the exact order.',
      );
    }
    if (decoded is! Map || decoded['code'] != 0) {
      throw _BingxRejected(
        decoded is Map && decoded['code'] is int ? decoded['code'] as int : -1,
      );
    }
    return decoded['data'];
  }

  Map<String, dynamic> _entryPlan(ExternalEffectAdapterRequest request) {
    request.validate();
    final plan = jsonDecode(request.canonicalPayloadJson);
    if (request.providerId != 'bingx' ||
        request.effectKind != 'order.entry.place' ||
        sha256.convert(utf8.encode(request.canonicalPayloadJson)).toString() !=
            request.payloadHashHex ||
        plan is! Map) {
      throw const FormatException('Unsupported BingX entry effect');
    }
    final p = Map<String, dynamic>.from(plan);
    if (p.length != 14 ||
        p['account_id'] != request.accountBindingId ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(request.accountBindingId) ||
        request.operationId != entryOperationId(p) ||
        p['symbol'] is! String ||
        !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(p['symbol'] as String) ||
        (p['symbol'] as String).length > 64 ||
        !['long', 'short'].contains(p['side']) ||
        !['1d', '4h', '1h', '30m', '15m', '5m'].contains(p['timeframe']) ||
        [
          'origin',
          'first_known',
          'prepared_at_ms',
          'expires_at_ms',
          'leverage',
        ].any((k) => p[k] is! int) ||
        [
          'line_price',
          'price',
          'quantity',
          'stop_price',
          'margin',
        ].any((k) => p[k] is! num || !(p[k] as num).isFinite || p[k] <= 0) ||
        p['origin'] >= p['first_known'] ||
        p['first_known'] > p['prepared_at_ms'] ||
        p['expires_at_ms'] <= p['prepared_at_ms'] ||
        p['expires_at_ms'] - p['prepared_at_ms'] > 48 * 60 * 60 * 1000 ||
        p['leverage'] < 1 ||
        p['leverage'] > 10000 ||
        (p['side'] == 'long' &&
            (p['price'] > p['line_price'] || p['stop_price'] >= p['price'])) ||
        (p['side'] == 'short' &&
            (p['price'] < p['line_price'] || p['stop_price'] <= p['price']))) {
      throw const FormatException('Invalid bounded entry request');
    }
    return p;
  }

  Future<Map<String, String>> _boundCredentials(
    ExternalEffectAdapterRequest request,
  ) async {
    final load = _credentials;
    if (load == null) throw StateError('No account scope for this effect');
    final credentials = await load(request);
    await verifyAccountBinding(request.accountBindingId, credentials);
    return credentials;
  }

  Future<String> _accountId(Map<String, String> credentials) async {
    final identity = await _signed(
      'GET',
      '/openApi/account/v1/uid',
      {},
      credentials,
    );
    final uid = identity is Map ? identity['uid']?.toString() : null;
    if (uid == null || !RegExp(r'^[0-9]{1,30}$').hasMatch(uid)) {
      throw const FormatException('BingX account identity is unreadable');
    }
    return sha256.convert(utf8.encode('bingx:LIVE:$uid')).toString();
  }

  Future<void> verifyAccountBinding(
    String accountId,
    Map<String, String> credentials,
  ) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(accountId) ||
        await _accountId(credentials) != accountId) {
      throw StateError('BingX account binding changed; reconnect your account');
    }
  }

  Future<List<Map<String, dynamic>>> _readOpenOrders(
    String symbol,
    Map<String, String> credentials,
  ) async {
    final data = await _signed('GET', '/openApi/swap/v2/trade/openOrders', {
      'symbol': symbol,
    }, credentials);
    final rows = data is Map ? data['orders'] : data;
    if (rows is! List || rows.length > 64) {
      throw const FormatException('BingX open-order evidence is unreadable');
    }
    final ids = <String>{};
    return rows
        .map<Map<String, dynamic>?>((row) {
          if (row is! Map) {
            throw const FormatException(
              'BingX open-order evidence is unreadable',
            );
          }
          final id = row['orderID'] ?? row['orderId'];
          final rowSymbol = row['symbol'];
          if (rowSymbol is! String ||
              !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(rowSymbol) ||
              (id is! String && id is! int) ||
              !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(id.toString()) ||
              !ids.add(id.toString()) ||
              (row['orderID'] != null &&
                  row['orderId'] != null &&
                  row['orderId'].toString() != id.toString())) {
            throw const FormatException(
              'BingX open-order evidence is unreadable',
            );
          }
          // BingX may ignore the symbol query and return another instrument.
          // Those rows are account-bound evidence, but not evidence for this
          // selected workspace instrument.
          if (rowSymbol != symbol) return null;
          String number(String name) {
            final raw = row[name];
            final value = raw is num ? raw : num.tryParse(raw.toString());
            if (value == null || !value.isFinite || value < 0) {
              throw const FormatException(
                'BingX open-order evidence is unreadable',
              );
            }
            return value.toString();
          }

          final quantity = number('origQty');
          final filled = number('executedQty');
          if (!['BUY', 'SELL'].contains(row['side']) ||
              !['BOTH', 'LONG', 'SHORT'].contains(row['positionSide']) ||
              ['type', 'status'].any(
                (k) =>
                    row[k] is! String ||
                    !RegExp(r'^[A-Z_]{1,32}$').hasMatch(row[k] as String),
              ) ||
              num.parse(filled) > num.parse(quantity)) {
            throw const FormatException(
              'BingX open-order evidence is unreadable',
            );
          }
          return <String, dynamic>{
            'order_id': id.toString(),
            'side': row['side'],
            'position_side': row['positionSide'],
            'type': row['type'],
            'status': row['status'],
            'price': number('price'),
            'stop_price':
                row['stopPrice'] == null || row['stopPrice'] == ''
                    ? '0'
                    : number('stopPrice'),
            'quantity': quantity,
            'filled_quantity': filled,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>> readOpenOrders(
    Map<String, dynamic> request,
    Map<String, String> credentials,
  ) async {
    final symbol = request['symbol'];
    if (request['kind'] != 'order.snapshot.read' ||
        request['scope'] != 'open' ||
        request['provider'] != 'bingx' ||
        symbol is! String ||
        symbol.length > 64 ||
        !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(symbol) ||
        request['account_id'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(request['account_id'] as String)) {
      throw const FormatException('Unsupported open-order read');
    }
    await verifyAccountBinding(request['account_id'] as String, credentials);
    final orders = await _readOpenOrders(symbol, credentials);
    return {
      'account_id': request['account_id'],
      'symbol': symbol,
      'orders': orders,
      'observed_at_ms': _clock().toUtc().millisecondsSinceEpoch,
    };
  }

  Future<Map<String, dynamic>> readEntry(
    ExternalEffectAdapterRequest request,
  ) async {
    final p = _entryPlan(request);
    final credentials = await _boundCredentials(request);
    final clientId = request.operationId.substring(0, 40);
    final data = await _signed('GET', '/openApi/swap/v2/trade/order', {
      'symbol': p['symbol'] as String,
      'clientOrderId': clientId,
    }, credentials);
    final order =
        data is Map && data['order'] is Map ? data['order'] as Map : data;
    if (order is! Map ||
        order['symbol'] != p['symbol'] ||
        order['clientOrderId'] != clientId ||
        order['side'] != (p['side'] == 'long' ? 'BUY' : 'SELL') ||
        ![
          'BOTH',
          p['side'] == 'long' ? 'LONG' : 'SHORT',
        ].contains(order['positionSide']) ||
        order['type'] != 'LIMIT') {
      throw const FormatException('Provider did not return this exact entry');
    }
    num number(dynamic raw) {
      final n = raw is num ? raw : num.tryParse(raw.toString());
      if (n == null || !n.isFinite || n < 0) {
        throw const FormatException('Invalid order evidence');
      }
      return n;
    }

    final id = (order['orderID'] ?? order['orderId'])?.toString();
    final qty = number(order['origQty']);
    final filled = number(order['executedQty']);
    final avg = number(order['avgPrice']);
    final status =
        const {
          'NEW': 'open',
          'PENDING': 'open',
          'PARTIALLY_FILLED': 'partial',
          'FILLED': 'filled',
          'CANCELED': 'cancelled',
          'CANCELLED': 'cancelled',
          'REJECTED': 'rejected',
          'EXPIRED': 'expired',
        }[order['status']];
    if (id == null ||
        !RegExp(r'^[0-9]{1,30}$').hasMatch(id) ||
        (request.providerReferenceId != null &&
            id != request.providerReferenceId) ||
        status == null ||
        qty != p['quantity'] ||
        number(order['price']) != p['price'] ||
        filled > qty ||
        (filled > 0 && avg <= 0) ||
        (status == 'filled' && filled != qty) ||
        (status == 'partial' && (filled == 0 || filled == qty))) {
      throw const FormatException(
        'Order identity, quantity, price or fill evidence does not match',
      );
    }
    return {
      'account_id': request.accountBindingId,
      'symbol': p['symbol'],
      'client_order_id': clientId,
      'order_id': id,
      'status': status,
      'filled_quantity': filled,
      'average_price': avg,
      'observed_at_ms': _clock().toUtc().millisecondsSinceEpoch,
    };
  }

  Future<List<Map<String, dynamic>>> _readPositions(
    String symbol,
    Map<String, String> credentials,
  ) async {
    final data = await _signed('GET', '/openApi/swap/v2/user/positions', {
      'symbol': symbol,
    }, credentials);
    if (data is! List || data.length > 64) {
      throw const FormatException('BingX position evidence is unreadable');
    }
    final ids = <String>{};
    final positions = <Map<String, dynamic>>[];
    for (final row in data) {
      if (row is! Map || row['symbol'] != symbol) {
        throw const FormatException('BingX position evidence is unreadable');
      }
      final amount = num.tryParse(row['positionAmt'].toString());
      if (amount == null || !amount.isFinite) {
        throw const FormatException('BingX position quantity is unreadable');
      }
      // Zero rows are provider evidence of no current exposure, not positions
      // to adopt. Every nonzero row must carry an exact usable identity.
      if (amount == 0) continue;
      final id = row['positionId'];
      final side = row['positionSide'];
      final average = num.tryParse(row['avgPrice'].toString());
      if ((id is! String && id is! int) ||
          !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(id.toString()) ||
          !ids.add(id.toString()) ||
          !['BOTH', 'LONG', 'SHORT'].contains(side) ||
          average == null ||
          !average.isFinite ||
          average <= 0) {
        throw const FormatException('BingX position identity is unreadable');
      }
      positions.add({
        'position_id': id.toString(),
        'side':
            side == 'BOTH'
                ? (amount > 0 ? 'long' : 'short')
                : (side == 'LONG' ? 'long' : 'short'),
        'quantity': amount.abs(),
        'average_price': average,
      });
    }
    return positions;
  }

  Future<Map<String, dynamic>> readLifecycle(
    ExternalEffectAdapterRequest request, {
    ExternalEffectAdapterRequest? exit,
  }) async {
    final plan = _entryPlan(request);
    final credentials = await _boundCredentials(request);
    final started = _clock().toUtc().millisecondsSinceEpoch;
    final entry = await readEntry(request);
    final positions = await _readPositions(
      plan['symbol'] as String,
      credentials,
    );
    final orders = await _readOpenOrders(plan['symbol'] as String, credentials);
    final exitEvidence = exit == null ? null : await readExit(exit);
    final finished = _clock().toUtc().millisecondsSinceEpoch;
    if (finished < started || finished - started > 60000) {
      throw StateError('Lifecycle read took too long; repeat observation');
    }
    return {
      'account_id': request.accountBindingId,
      'symbol': plan['symbol'],
      'entry': entry,
      'positions': positions,
      'orders': orders,
      'observed_at_ms': finished,
      if (exitEvidence != null) 'exit': exitEvidence,
    };
  }

  ExternalEffectAdapterResult _receipt(
    ExternalEffectAdapterRequest request,
    Map<String, dynamic> evidence,
  ) => ExternalEffectAdapterResult(
    status: ExternalEffectAdapterStatus.succeeded,
    receipt: ExternalEffectReceipt(
      operationId: request.operationId,
      providerId: 'bingx',
      providerReceiptId: evidence['order_id'] as String,
      evidenceHashHex:
          sha256.convert(utf8.encode(jsonEncode(evidence))).toString(),
      receivedAtUtc: _clock().toUtc().toIso8601String(),
    ),
  );

  Future<(Map<String, String>, bool)> _entryPreflight(
    ExternalEffectAdapterRequest request,
  ) async {
    final p = _entryPlan(request);
    final credentials = await _boundCredentials(request);
    final symbol = p['symbol'] as String;
    final open = await _readOpenOrders(symbol, credentials);
    if (open.isNotEmpty) {
      final id = open.first['order_id'];
      throw StateError('Open $symbol order $id already exists; no entry sent');
    }
    if ((await _readPositions(symbol, credentials)).isNotEmpty) {
      throw StateError('A $symbol position already exists; no entry sent');
    }
    final mode = await _signed(
      'GET',
      '/openApi/swap/v1/positionSide/dual',
      {},
      credentials,
    );
    final hedgeMode = switch (mode is Map ? mode['dualSidePosition'] : null) {
      true || 'true' => true,
      false || 'false' => false,
      _ => null,
    };
    if (hedgeMode == null) {
      throw const FormatException(
        'BingX position mode is unreadable; no entry sent',
      );
    }
    final leverage = await _readLeverage(symbol, credentials);
    if (leverage[p['side'] == 'long' ? 'long' : 'short'] != p['leverage']) {
      throw StateError('Exchange leverage changed; prepare the entry again');
    }
    if (_authorize == null) throw StateError('Entry is not authorized');
    await _authorize(p);
    final now = _clock().toUtc().millisecondsSinceEpoch;
    if (now < p['prepared_at_ms'] || now > p['expires_at_ms']) {
      throw StateError('Prepared entry expired');
    }
    return (credentials, hedgeMode);
  }

  @override
  Future<ExternalEffectAdapterResult> deliver(
    ExternalEffectAdapterRequest request,
  ) async {
    if (request.effectKind == 'position.exit.place') return _placeExit(request);
    if (request.effectKind == 'order.entry.cancel') {
      return _cancelEntry(request);
    }
    final p = _entryPlan(request);
    final (Map<String, String>, bool) ready;
    try {
      ready = await _entryPreflight(request);
    } catch (error) {
      // Only reads and WASM validation ran. No provider write was dispatched.
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'entry_not_sent',
        errorMessage: 'No entry sent: $error',
      );
    }
    final credentials = ready.$1;
    final symbol = p['symbol'] as String;
    try {
      // Only this method can POST. Never retry a possibly delivered request.
      await _signed('POST', '/openApi/swap/v2/trade/order', {
        'symbol': symbol,
        'side': p['side'] == 'long' ? 'BUY' : 'SELL',
        'positionSide':
            ready.$2 ? (p['side'] == 'long' ? 'LONG' : 'SHORT') : 'BOTH',
        'type': 'LIMIT',
        'timeInForce': 'PostOnly',
        'quantity': p['quantity'].toString(),
        'price': p['price'].toString(),
        'clientOrderId': request.operationId.substring(0, 40),
        'stopLoss': jsonEncode({
          'type': 'STOP_MARKET',
          'stopPrice': p['stop_price'],
          'workingType': 'CONTRACT_PRICE',
        }),
      }, credentials);
    } on _BingxRejected catch (e) {
      if (e.code > 0 && e.code != 101481) {
        return ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.terminalFailure,
          errorCode: 'provider_rejected',
          errorMessage: 'BingX rejected entry (code ${e.code})',
        );
      }
    }
    return reconcile(request);
  }

  @override
  Future<ExternalEffectAdapterResult> reconcile(
    ExternalEffectAdapterRequest request,
  ) async {
    if (request.effectKind == 'position.exit.place') {
      try {
        return _receipt(request, await readExit(request));
      } catch (_) {
        return const ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'exit_unverified',
          errorMessage: 'Exact exit unavailable; no automatic resubmission',
        );
      }
    }
    if (request.effectKind == 'order.entry.cancel') {
      try {
        final evidence = await readEntry(_entryForCancellation(request));
        if ([
          'cancelled',
          'filled',
          'rejected',
          'expired',
        ].contains(evidence['status'])) {
          // Terminal resolution is not necessarily cancellation: a racing
          // fill remains a fill in the provider evidence returned to WASM.
          return _receipt(request, evidence);
        }
      } catch (_) {}
      return const ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.unresolved,
        errorCode: 'cancel_unverified',
        errorMessage:
            'Cancellation unverified; reconcile the exact order without another DELETE',
      );
    }
    try {
      return _receipt(request, await readEntry(request));
    } catch (_) {
      // Not-found is not proof of non-delivery. Do not authorize a new POST.
      return const ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.unresolved,
        errorCode: 'entry_unverified',
        errorMessage: 'Exact order unavailable; no automatic resubmission',
      );
    }
  }

  Future<ExternalEffectAdapterResult> _cancelEntry(
    ExternalEffectAdapterRequest request,
  ) async {
    final entry = _entryForCancellation(request);
    final plan = _entryPlan(entry);
    late Map<String, String> credentials;
    try {
      if (_authorize == null) {
        throw StateError('Cancellation is not authorized');
      }
      await _authorize(plan);
      credentials = await _boundCredentials(entry);
      if ((await _readPositions(plan['symbol'], credentials)).isNotEmpty) {
        throw StateError('A position exists; no entry replacement');
      }
      final evidence = await readEntry(entry);
      if (evidence['status'] != 'open' || evidence['filled_quantity'] != 0) {
        throw StateError('Entry is no longer open and unfilled');
      }
      await _authorize(plan);
    } catch (_) {
      return const ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'cancel_not_sent',
        errorMessage:
            'No cancellation sent: refresh order, position, line and authority',
      );
    }
    try {
      // Only this exact order, never allOpenOrders. Any uncertainty after
      // dispatch is read-only reconciliation, not permission to repeat DELETE.
      await _signed('DELETE', '/openApi/swap/v2/trade/order', {
        'symbol': plan['symbol'],
        'orderId': entry.providerReferenceId!,
      }, credentials);
    } catch (_) {}
    return reconcile(request);
  }

  @override
  Future<ExternalEffectAdapterResult> resolveRequiredAction(
    ExternalEffectAdapterRequest request,
    ExternalEffectRequiredAction action,
    String response,
  ) async => throw StateError('BingX has no provider challenge flow');

  Future<Map<String, int>> _readLeverage(
    String symbol,
    Map<String, String> credentials,
  ) async {
    final data = await _signed('GET', '/openApi/swap/v2/trade/leverage', {
      'symbol': symbol,
    }, credentials);
    if (data is! Map) {
      throw const FormatException('Instrument leverage unavailable');
    }
    int value(String name) {
      final n = num.tryParse(data[name].toString());
      if (n == null || !n.isFinite || n != n.toInt() || n < 1 || n > 10000) {
        throw const FormatException('Invalid exchange leverage');
      }
      return n.toInt();
    }

    return {'long': value('longLeverage'), 'short': value('shortLeverage')};
  }

  Future<Map<String, dynamic>> readAccount(
    Map<String, dynamic> request,
    Map<String, String> credentials,
  ) async {
    final symbol = request['symbol'];
    if (!const {
          'account.connect',
          'account.snapshot.read',
        }.contains(request['kind']) ||
        request['provider'] != 'bingx' ||
        symbol is! String ||
        symbol.length > 64 ||
        !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(symbol)) {
      throw const FormatException(
        'Account preview supports BingX LIVE USDT contracts',
      );
    }
    final key = credentials['api_key']?.trim() ?? '';
    final secret = credentials['secret_key']?.trim() ?? '';
    if ([key, secret].any(
      (s) =>
          s.isEmpty ||
          s.length > 512 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s),
    )) {
      throw const FormatException('Enter both BingX API and secret keys');
    }
    Future<dynamic> signed(String path) async {
      return _signed('GET', path, {}, {'api_key': key, 'secret_key': secret});
    }

    final identity = await signed('/openApi/account/v1/uid');
    final uid = identity is Map ? identity['uid']?.toString() : null;
    if (uid == null || !RegExp(r'^[0-9]{1,30}$').hasMatch(uid)) {
      throw const FormatException('BingX did not provide an exact account UID');
    }
    final accountId = sha256.convert(utf8.encode('bingx:LIVE:$uid')).toString();
    if (request['kind'] == 'account.snapshot.read' &&
        request['account_id'] != accountId) {
      throw StateError('Account binding changed; reconnect your BingX account');
    }
    final balance = await signed('/openApi/swap/v3/user/balance');
    if (balance is! List) {
      throw const FormatException('Invalid futures balance');
    }
    final matches =
        balance.where((b) => b is Map && b['asset'] == 'USDT').toList();
    if (matches.length != 1) {
      throw const FormatException('USDT futures balance unavailable');
    }
    final leverage = await _readLeverage(symbol, {
      'api_key': key,
      'secret_key': secret,
    });
    final contractUri = Uri.https(
      'open-api.bingx.com',
      '/openApi/swap/v2/quote/contracts',
      {'symbol': symbol},
    );
    final raw =
        await (_read == null ? _httpRead(contractUri) : _read(contractUri));
    if (utf8.encode(raw).length > 512 * 1024) {
      throw const FormatException('Contract response too large');
    }
    final contracts = jsonDecode(raw);
    if (contracts is! Map ||
        contracts['code'] != 0 ||
        contracts['data'] is! List) {
      throw const FormatException('Instrument constraints unavailable');
    }
    final rows =
        (contracts['data'] as List)
            .where((c) => c is Map && c['symbol'] == symbol)
            .toList();
    if (rows.length != 1) {
      throw const FormatException('Instrument constraints are ambiguous');
    }
    final contract = rows.single as Map;
    if (contract['status'] != 1 ||
        !(contract['apiStateOpen'] == true ||
            contract['apiStateOpen'] == 'true')) {
      throw const FormatException(
        'Instrument is not available for API entries',
      );
    }
    num number(dynamic raw) {
      final n = raw is num ? raw : num.tryParse(raw.toString());
      if (n == null || !n.isFinite || n < 0) {
        throw const FormatException('Invalid account or contract number');
      }
      return n;
    }

    int integer(dynamic raw, int min, int max) {
      final n = number(raw);
      if (n != n.toInt() || n < min || n > max) {
        throw const FormatException('Invalid exchange precision or leverage');
      }
      return n.toInt();
    }

    return {
      'symbol': symbol,
      'endpoint': 'LIVE',
      'account_id': accountId,
      'account_label':
          'BingX LIVE / account ending ${uid.substring(uid.length > 4 ? uid.length - 4 : 0)}',
      'available_margin': number((matches.single as Map)['availableMargin']),
      'long_leverage': leverage['long'],
      'short_leverage': leverage['short'],
      'price_precision': integer(contract['pricePrecision'], 0, 12),
      'quantity_precision': integer(contract['quantityPrecision'], 0, 12),
      'min_quantity': number(contract['tradeMinQuantity']),
      'min_notional': number(contract['tradeMinUSDT']),
      'observed_at_ms': _clock().toUtc().millisecondsSinceEpoch,
    };
  }

  Future<List<String>> readInstruments(Map<String, dynamic> source) async {
    if (source['kind'] != 'market.instruments.read' ||
        source['provider'] != 'bingx') {
      throw const FormatException('Unsupported instrument source');
    }
    final uri = Uri.https(
      'open-api.bingx.com',
      '/openApi/swap/v2/quote/contracts',
      {'timestamp': _clock().toUtc().millisecondsSinceEpoch.toString()},
    );
    final raw =
        await (_read == null
            ? _httpRead(uri, maxBytes: 2 * 1024 * 1024)
            : _read(uri));
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('Instrument response is too large');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['code'] != 0 || decoded['data'] is! List) {
      throw const FormatException('Exchange instrument list is unavailable');
    }
    final data = decoded['data'] as List;
    if (data.isEmpty || data.length > 4096) {
      throw const FormatException('Invalid instrument count');
    }
    final symbols = <String>{};
    for (final row in data) {
      if (row is! Map) {
        throw const FormatException('Invalid instrument');
      }
      // Provider availability, not strategy filtering or a local whitelist.
      if (row['status'] != 1 ||
          !(row['apiStateOpen'] == 'true' || row['apiStateOpen'] == true)) {
        continue;
      }
      final symbol = row['symbol'];
      if (symbol is! String ||
          symbol.length > 64 ||
          !RegExp(r'^[A-Z0-9]+-[A-Z0-9]+$').hasMatch(symbol)) {
        throw const FormatException('Invalid instrument symbol');
      }
      symbols.add(symbol);
    }
    if (symbols.isEmpty) {
      throw const FormatException('No available instruments returned');
    }
    return symbols.toList()..sort();
  }

  Future<Map<String, dynamic>> readCandles(Map<String, dynamic> request) async {
    final symbol = request['symbol'];
    final timeframe = request['timeframe'];
    final limit = request['limit'];
    const spans = {
      '1d': 86400000,
      '4h': 14400000,
      '1h': 3600000,
      '30m': 1800000,
      '15m': 900000,
      '5m': 300000,
    };
    if (request['kind'] != 'market.candles.read' ||
        request['provider'] != 'bingx' ||
        symbol is! String ||
        !RegExp(r'^[A-Z0-9]+-[A-Z0-9]+$').hasMatch(symbol) ||
        symbol.length > 64 ||
        !spans.containsKey(timeframe) ||
        limit is! int ||
        limit < 1 ||
        limit > 600) {
      throw const FormatException('Unsupported public market request');
    }
    final now = _clock().toUtc();
    final last = _lastRequest;
    if (_read == null && last != null) {
      final wait = 1100 - now.difference(last).inMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }
    _lastRequest = _clock().toUtc();
    final uri =
        Uri.https('open-api.bingx.com', '/openApi/swap/v3/quote/klines', {
          'symbol': symbol,
          'interval': timeframe.toString(),
          'limit': limit.toString(),
          'timestamp': _lastRequest!.millisecondsSinceEpoch.toString(),
        });
    final raw = await (_read == null ? _httpRead(uri) : _read(uri));
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['code'] != 0 || decoded['data'] is! List) {
      throw const FormatException('Exchange did not return usable market data');
    }
    final data = decoded['data'] as List;
    if (data.isEmpty || data.length > 600) {
      throw const FormatException('Invalid candle count');
    }
    num number(Object? value) {
      final parsed = value is num ? value : num.tryParse(value.toString());
      if (parsed == null || !parsed.isFinite) {
        throw const FormatException('Invalid candle number');
      }
      return parsed;
    }

    final candles = <List<num>>[];
    for (final row in data) {
      final List<num> candle;
      if (row is Map) {
        candle = [
          number(row['time']),
          number(row['open']),
          number(row['high']),
          number(row['low']),
          number(row['close']),
        ];
      } else if (row is List && row.length >= 5) {
        candle = row.take(5).map(number).toList();
      } else {
        throw const FormatException('Unsupported candle shape');
      }
      final time = candle[0];
      if (time != time.toInt() ||
          time < 0 ||
          time.toInt() % spans[timeframe]! != 0 ||
          candle.skip(1).any((p) => p <= 0) ||
          candle[2] < candle[1] ||
          candle[2] < candle[4] ||
          candle[3] > candle[1] ||
          candle[3] > candle[4] ||
          candle[3] > candle[2]) {
        throw const FormatException('Invalid OHLC candle');
      }
      candles.add([time.toInt(), ...candle.skip(1)]);
    }
    candles.sort((a, b) => a[0].compareTo(b[0]));
    if (candles.asMap().entries.any(
      (e) =>
          e.key > 0 && e.value[0] - candles[e.key - 1][0] != spans[timeframe],
    )) {
      throw const FormatException(
        'Exchange candles are duplicated or incomplete',
      );
    }
    final observed = _clock().toUtc().millisecondsSinceEpoch;
    if (candles.last[0] > observed ||
        observed - candles.last[0] >= spans[timeframe]! * 2) {
      throw const FormatException('Exchange market evidence is stale');
    }
    final closed =
        candles.where((c) => c[0] + spans[timeframe]! <= observed).toList();
    if (closed.isEmpty) {
      throw const FormatException('No closed candles available');
    }
    return {
      'symbol': symbol,
      'timeframe': timeframe,
      'candles': closed,
      'current_price': candles.last[4],
      if (candles.last[0] + spans[timeframe]! > observed)
        'current_candle': candles.last,
      'observed_at_ms': observed,
    };
  }

  Future<String> _httpRead(
    Uri uri, {
    int maxBytes = 512 * 1024,
    Map<String, String> headers = const {},
    String method = 'GET',
  }) async {
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set('X-SOURCE-KEY', 'BX-AI-SKILL');
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw HttpException('Market request failed: ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw const FormatException('Market response is too large');
        }
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }
}

class _BingxRejected implements Exception {
  final int code;
  const _BingxRejected(this.code);
  @override
  String toString() => 'BingX rejected request (code $code)';
}
