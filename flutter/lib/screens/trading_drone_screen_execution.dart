part of 'trading_drone_screen.dart';

extension _TradingDroneExecution on _TradingDroneScreenState {
  Future<void> _executeLastIntent() async {
    await _module.uiLog.log(
      'bingx.exchange.execute.tap',
      'running=$_executing hasIntent=${_lastIntentResponse?.status == PluginHostApiStatus.executed}',
    );
    if (_executing) return;
    final response = _lastIntentResponse;
    final result = response?.result;
    if (response?.status != PluginHostApiStatus.executed || result == null) {
      await _module.uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=no_intent status=${response?.status.name ?? "none"}',
      );
      await _showSnack('Run a BingX intent first');
      return;
    }
    final currentSymbol = _symbolController.text.trim().toUpperCase();
    final intentSymbol = result['symbol']?.toString().trim().toUpperCase();
    if (currentSymbol.isNotEmpty &&
        intentSymbol != null &&
        intentSymbol.isNotEmpty &&
        currentSymbol != intentSymbol) {
      await _module.uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=stale_intent current_symbol=$currentSymbol intent_symbol=$intentSymbol',
      );
      await _showSnack('Run a fresh intent for $currentSymbol first');
      return;
    }

    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _module.uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=no_credentials',
      );
      await _showSnack('Save BingX API credentials first');
      return;
    }

    _updateState(() {
      _executing = true;
    });
    try {
      final useCaseResult = await _module.executionUseCase.execute(
        screen: 'trading_drone',
        rawIntentResult: result,
        credentials: credentials,
        riskPolicy: _TradingDroneScreenState._executionRiskPolicy,
        fallbackEquityQuote: _TradingDroneScreenState._fallbackRiskEquityQuote,
        testOrder: _useTestOrderEndpoint,
        preparedDecision: _lastPreparedLiveDecision,
        refreshDecision:
            () => _computeLiveDecision(
              symbol: intentSymbol ?? currentSymbol,
              peerHex: result['peer_hex']?.toString().trim() ?? '',
              silent: true,
              forceConsensusSignable:
                  (result['peer_hex']?.toString().trim() ?? '').isEmpty,
              zoneEvaluationSide: result['side']?.toString(),
            ),
      );
      for (final diagnostic in useCaseResult.diagnostics) {
        await _module.uiLog.log('bingx.exchange.risk_detail', diagnostic);
      }
      if (useCaseResult.status ==
          BingxFuturesExchangeExecutionUseCaseStatus.invalidIntent) {
        await _module.uiLog.log(
          'bingx.exchange.execute.parse_error',
          useCaseResult.errorMessage ?? 'invalid intent',
        );
        await _showSnack(
          useCaseResult.errorMessage ?? 'Invalid intent',
          seconds: 3,
        );
        return;
      }
      if (useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus.staleIntent ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus.executionPaused ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus.mandateBlocked ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus
                  .duplicateLiquidityEvent ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus
                  .effectClaimUnavailable) {
        await _module.uiLog.log(
          'bingx.exchange.execute.guard',
          'blocked=${useCaseResult.errorCode ?? useCaseResult.status.name}',
        );
        await _showSnack(
          useCaseResult.errorMessage ?? 'Execution blocked',
          seconds: 4,
        );
        return;
      }
      if (useCaseResult.status ==
          BingxFuturesExchangeExecutionUseCaseStatus.riskUnavailable) {
        await _module.uiLog.log(
          'bingx.exchange.risk_error',
          useCaseResult.errorCode ?? 'risk_unavailable',
        );
        await _showSnack(
          useCaseResult.errorMessage ?? 'Risk check unavailable',
        );
        return;
      }
      final riskDecision = useCaseResult.riskDecision!;
      if (useCaseResult.status ==
          BingxFuturesExchangeExecutionUseCaseStatus.riskBlocked) {
        final shortHash = riskDecision.decisionHashHex.substring(0, 12);
        final executionEnvelope = useCaseResult.executionEnvelope;
        await _module.uiLog.log(
          'bingx.exchange.risk_blocked',
          'code=${riskDecision.reasonCode} hash=$shortHash '
              'risk=${riskDecision.tradeRiskQuoteDecimal} '
              'limit=${riskDecision.tradeRiskLimitQuoteDecimal}',
        );
        if (executionEnvelope != null) {
          await _module.uiLog.log(
            'drone.execution.envelope',
            'hash=${executionEnvelope.envelopeHashHex} '
                'kind=execution screen=trading_drone risk=blocked',
          );
        }
        await _showSnack(
          '${riskDecision.reasonMessage} ($shortHash)',
          seconds: 4,
        );
        return;
      }
      await _module.uiLog.log(
        'bingx.exchange.risk_allowed',
        'hash=${riskDecision.decisionHashHex.substring(0, 12)} '
            'max_qty=${riskDecision.maxAllowedQuantityDecimal} '
            'risk=${riskDecision.tradeRiskQuoteDecimal}',
      );
      final payload = useCaseResult.payload!;
      await _module.uiLog.log(
        'bingx.exchange.execute.intent',
        'symbol=${payload.symbol} side=${payload.side} type=${payload.orderType} '
            'entry=${payload.entryMode} limit=${payload.limitPriceDecimal ?? "-"} '
            'trigger=${payload.triggerPriceDecimal ?? "-"} '
            'sl=${payload.stopLossDecimal ?? "-"} '
            'tp=${payload.takeProfitDecimal ?? "-"} '
            'tif=${payload.timeInForce ?? "-"}',
      );
      final queued = useCaseResult.queuedExecution!;
      final executionEnvelope = useCaseResult.executionEnvelope!;
      final safeMessage = queued.execution.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _module.uiLog.log(
        'bingx.exchange.execute',
        'symbol=${payload.symbol} side=${payload.side} type=${payload.orderType} '
            'test=${_useTestOrderEndpoint ? "yes" : "no"} attempts=${queued.attempts} '
            'cache=${queued.fromIdempotentCache ? "hit" : "miss"} '
            'success=${queued.execution.isSuccess} http=${queued.execution.httpStatusCode} '
            'code=${queued.execution.exchangeCode} endpoint=${queued.execution.endpointPath} '
            'orderId=${queued.execution.orderId ?? "-"} msg=$safeMessage',
      );
      await _module.uiLog.log(
        'drone.execution.envelope',
        'hash=${executionEnvelope.envelopeHashHex} '
            'kind=execution screen=trading_drone',
      );
      if (!mounted) return;
      _updateState(() {
        _lastExecution = queued.execution;
        _lastExecutionAttempts = queued.attempts;
        _lastExecutionFromCache = queued.fromIdempotentCache;
      });

      if (useCaseResult.status ==
          BingxFuturesExchangeExecutionUseCaseStatus.validated) {
        await _showSnack(
          'Exact request validated. No exchange order was created.',
          seconds: 4,
        );
      } else if (queued.execution.isSuccess) {
        final orderId = queued.execution.orderId?.trim();
        _registerManagedOrderId(
          orderId,
          symbol: payload.symbol,
          provenance:
              orderId == null || orderId.isEmpty
                  ? null
                  : _buildManagedOrderProvenance(
                    orderId: orderId,
                    payload: payload,
                    result: result,
                    testOrder: _useTestOrderEndpoint,
                    credentials: credentials,
                  ),
        );
        _startOpenOrdersAutoTracking(
          symbol: payload.symbol,
          orderId: queued.execution.orderId,
        );
        unawaited(_fetchOpenOrders(silent: true));
        await _showSnack(
          'Order sent${queued.execution.orderId == null ? '' : ' · id ${queued.execution.orderId}'}'
          '${queued.fromIdempotentCache ? ' · idempotent cache' : ''}',
        );
      } else {
        await _showSnack(
          'Order failed: ${queued.execution.exchangeCode} ${queued.execution.exchangeMessage}',
          seconds: 4,
        );
      }
    } catch (error) {
      await _module.uiLog.log('bingx.exchange.error', '$error');
      await _showSnack('BingX execution failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        _updateState(() {
          _executing = false;
        });
      }
    }
  }

  Future<BingxFuturesRiskDecision?> _evaluateExecutionRisk({
    required BingxFuturesIntentPayload payload,
    required Map<String, dynamic> rawIntentResult,
  }) async {
    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return null;
    }
    final evaluation = await _module.executionUseCase.evaluateRisk(
      payload: payload,
      rawIntentResult: rawIntentResult,
      credentials: credentials,
      riskPolicy: _TradingDroneScreenState._executionRiskPolicy,
      fallbackEquityQuote: _TradingDroneScreenState._fallbackRiskEquityQuote,
    );
    for (final diagnostic in evaluation.diagnostics) {
      await _module.uiLog.log('bingx.exchange.risk_detail', diagnostic);
    }
    if (evaluation.decision == null) {
      await _module.uiLog.log(
        'bingx.exchange.risk_error',
        evaluation.errorCode ?? 'risk_unavailable',
      );
      await _showSnack(evaluation.errorMessage ?? 'Risk check unavailable');
    }
    return evaluation.decision;
  }

  Future<void> _fetchOpenOrders({bool silent = false}) async {
    if (_fetchingOpenOrders) return;
    final credentials = await _ensureCredentialsLoaded(silent: silent);
    if (credentials == null) {
      if (!silent) {
        await _showSnack('Save BingX API credentials first');
      }
      return;
    }
    _updateState(() {
      _fetchingOpenOrders = true;
    });
    try {
      final result = await _module.exchangeService.getOpenOrders(
        credentials: credentials,
      );
      final message = result.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _module.uiLog.log(
        'bingx.exchange.open_orders',
        'symbol=${result.symbol} success=${result.isSuccess} '
            'http=${result.httpStatusCode} code=${result.exchangeCode} '
            'count=${result.orders.length} endpoint=${result.endpointPath} msg=$message',
      );
      if (!mounted) return;
      final allOrders = result.orders;
      final reconciliation = await _module.executionUseCase
          .reconcileManagedOrders(credentials: credentials, openOrders: result);
      if (!mounted) return;
      _applyManagedOrderReconciliation(reconciliation);
      for (final order in allOrders) {
        if (_managedOrderIds.contains(order.orderId)) {
          _managedOrderSymbols[order.orderId] = order.symbol.toUpperCase();
        }
      }
      final managedOrders = allOrders
          .where((order) => _managedOrderIds.contains(order.orderId))
          .toList(growable: false);
      final lifecycleRevisionBeforeRevalidation =
          _managedOrderLifecycleRevision;
      if (result.isSuccess && managedOrders.isNotEmpty) {
        await _revalidateManagedOpenOrders(
          credentials: credentials,
          managedOrders: managedOrders,
          silent: silent,
        );
      }
      final snapshotInvalidatedByLifecycle =
          lifecycleRevisionBeforeRevalidation != _managedOrderLifecycleRevision;
      _updateState(() {
        _lastOpenOrdersRead = result;
        if (result.isSuccess) {
          _openOrders = allOrders;
        }
        if (result.isSuccess && managedOrders.isNotEmpty) {
          _cancelOrderIdController.text = managedOrders.first.orderId;
        }
      });
      final trackedOrderId = _trackedOrderId;
      if (trackedOrderId != null && trackedOrderId.isNotEmpty) {
        if (result.isSuccess) {
          if (snapshotInvalidatedByLifecycle) {
            await _module.uiLog.log(
              'bingx.exchange.tracking.skip',
              'symbol=${result.symbol} orderId=$trackedOrderId '
                  'reason=stale_snapshot_after_lifecycle_change',
            );
            return;
          }
          final trackedStillOpen = allOrders.any(
            (order) => order.orderId == trackedOrderId,
          );
          await _module.uiLog.log(
            'bingx.exchange.tracking.check',
            'symbol=${result.symbol} orderId=$trackedOrderId '
                'open=${trackedStillOpen ? "yes" : "no"} '
                'managedCount=${managedOrders.length} totalCount=${allOrders.length}',
          );
          if (!trackedStillOpen) {
            _managedOrderIds.remove(trackedOrderId);
            _managedOrderSymbols.remove(trackedOrderId);
            _managedOrderProvenance.remove(trackedOrderId);
            _managedOrderLifecycleRevision += 1;
            final remainingManagedOrders = allOrders
                .where((order) => _managedOrderIds.contains(order.orderId))
                .toList(growable: false);
            if (remainingManagedOrders.isNotEmpty) {
              final nextTrackedOrderId = remainingManagedOrders.first.orderId;
              _trackedOrderId = nextTrackedOrderId;
              _cancelOrderIdController.text = nextTrackedOrderId;
              await _persistOpenOrdersTrackingState(
                source: 'tracked_order_closed_rotate',
              );
              await _module.uiLog.log(
                'bingx.exchange.tracking.rotate',
                'symbol=${result.symbol} previous=$trackedOrderId next=$nextTrackedOrderId '
                    'managedCount=${remainingManagedOrders.length}',
              );
            } else {
              _stopOpenOrdersAutoTracking(reason: 'order_closed');
              if (!silent) {
                await _showSnack('Tracked order is no longer open');
              }
            }
          }
        } else {
          await _module.uiLog.log(
            'bingx.exchange.tracking.skip',
            'symbol=${result.symbol} orderId=$trackedOrderId '
                'reason=open_orders_failed code=${result.exchangeCode} '
                'http=${result.httpStatusCode}',
          );
        }
      }
      if (!silent) {
        await _showSnack(
          result.isSuccess
              ? 'Open orders: ${allOrders.length} · drone: ${managedOrders.length}'
              : 'Open orders failed: ${result.exchangeCode}',
          seconds: result.isSuccess ? 2 : 4,
        );
      }
    } catch (error) {
      await _module.uiLog.log('bingx.exchange.open_orders.error', '$error');
      if (!silent) {
        await _showSnack('Fetch open orders failed: $error', seconds: 3);
      }
    } finally {
      if (mounted) {
        _updateState(() {
          _fetchingOpenOrders = false;
        });
      }
    }
  }

  void _applyManagedOrderReconciliation(
    BingxFuturesManagedOrderReconciliationResult reconciliation,
  ) {
    final state = reconciliation.state;
    if (state == null ||
        reconciliation.capsuleRootHex != _module.activeCapsuleRootHex()) {
      return;
    }
    _managedOrderIds
      ..clear()
      ..addAll(state.managedOrderIds);
    _managedOrderSymbols
      ..clear()
      ..addAll(state.managedOrderSymbols);
    _managedOrderProvenance
      ..clear()
      ..addAll(state.managedOrderProvenance);
    _trackedOrdersSymbol = state.trackedSymbol;
    _trackedOrderId = state.trackedOrderId;
    _cancelOrderIdController.text = state.trackedOrderId ?? '';
    _managedOrderLifecycleRevision += 1;
    unawaited(
      _module.uiLog.log(
        'bingx.exchange.tracking.reconcile',
        'active=${reconciliation.activeCount} '
            'terminal=${reconciliation.terminalCount} '
            'unresolved=${reconciliation.unresolvedCount} '
            'trackedOrderId=${state.trackedOrderId ?? "-"}',
      ),
    );
    if (tradingReconciliationResumeSymbol(state) == null) {
      _stopOpenOrdersAutoTracking(reason: 'no_managed_open_orders');
    }
  }

  Future<void> _revalidateManagedOpenOrders({
    required BingxFuturesApiCredentials credentials,
    required List<BingxFuturesOpenOrder> managedOrders,
    required bool silent,
  }) async {
    final bySymbol = <String, List<BingxFuturesOpenOrder>>{};
    for (final order in managedOrders) {
      final symbol = order.symbol.trim().toUpperCase();
      if (symbol.isEmpty) continue;
      bySymbol.putIfAbsent(symbol, () => <BingxFuturesOpenOrder>[]).add(order);
    }

    var canceled = 0;
    final replacementLifecycleKeys = <String>{};
    for (final entry in bySymbol.entries) {
      final actionableDecision = await _computeLiveDecision(
        symbol: entry.key,
        peerHex: '',
        silent: true,
        forceConsensusSignable: true,
      );
      if (actionableDecision == null) {
        await _module.uiLog.log(
          'bingx.exchange.revalidate.skip',
          'symbol=${entry.key} reason=live_decision_unavailable '
              'orders=${entry.value.length}',
        );
        continue;
      }
      final structuralDecisions = <String, BingxFuturesLiveDecisionResult?>{};

      for (final order in entry.value) {
        if (!_managedOrderIds.contains(order.orderId)) continue;
        final structuralSide = tradingManagedOrderStructuralSide(order.side);
        var revalidationDecision = actionableDecision;
        // Entry confirmation is short-lived; a live order belongs to its
        // structural side until that projection becomes invalid.
        if (structuralSide != null) {
          if (!structuralDecisions.containsKey(structuralSide)) {
            structuralDecisions[structuralSide] = await _computeLiveDecision(
              symbol: entry.key,
              peerHex: '',
              silent: true,
              forceConsensusSignable: true,
              zoneEvaluationSide: structuralSide,
            );
          }
          final structuralDecision = structuralDecisions[structuralSide];
          if (structuralDecision == null) {
            await _module.uiLog.log(
              'bingx.exchange.revalidate.skip',
              'symbol=${entry.key} orderId=${order.orderId} '
                  'reason=structural_decision_unavailable side=$structuralSide',
            );
            continue;
          }
          revalidationDecision = structuralDecision;
        }
        final provenance = _managedOrderProvenance[order.orderId];
        final verdict = _module.orderRevalidation.revalidate(
          order: order,
          liveDecision: revalidationDecision,
        );
        await _module.uiLog.log(
          'bingx.exchange.revalidate',
          'symbol=${order.symbol} orderId=${order.orderId} '
              'action=${verdict.action.name} reason=${verdict.reasonCode} '
              'live_hash=${revalidationDecision.liveDecisionHashHex.substring(0, 12)}',
        );
        if (!verdict.shouldCancel) continue;

        final cancel = await _module.exchangeService.cancelOrder(
          credentials: credentials,
          symbol: order.symbol,
          orderId: order.orderId,
        );
        await _module.uiLog.log(
          'bingx.exchange.revalidate.cancel',
          'symbol=${order.symbol} orderId=${order.orderId} '
              'success=${cancel.isSuccess} code=${cancel.exchangeCode} '
              'reason=${verdict.reasonCode}',
        );
        if (!cancel.isSuccess) continue;
        canceled += 1;
        _managedOrderIds.remove(order.orderId);
        _managedOrderSymbols.remove(order.orderId);
        _managedOrderProvenance.remove(order.orderId);
        _managedOrderLifecycleRevision += 1;
        if (_trackedOrderId == order.orderId) {
          _trackedOrderId = null;
        }
        if (provenance == null) {
          await _module.uiLog.log(
            'bingx.exchange.replace.skip',
            'symbol=${order.symbol} orderId=${order.orderId} '
                'reason=replacement_provenance_missing',
          );
          continue;
        }
        if (!actionableDecision.canPrepareIntent) {
          await _module.uiLog.log(
            'bingx.exchange.replace.skip',
            'symbol=${order.symbol} orderId=${order.orderId} '
                'reason=structural_revalidation_cancel_only',
          );
          continue;
        }
        try {
          await _replaceCanceledManagedOrder(
            credentials: credentials,
            provenance: provenance,
            liveDecision: actionableDecision,
            cancellationReasonCode: verdict.reasonCode,
            replacementLifecycleKeys: replacementLifecycleKeys,
          );
        } catch (error) {
          await _module.uiLog.log(
            'bingx.exchange.replace.error',
            'oldOrderId=${provenance.orderId} symbol=${provenance.symbol} '
                'error=$error',
          );
        }
      }
    }

    if (canceled > 0) {
      await _persistOpenOrdersTrackingState(source: 'revalidate_cancel');
      if (!silent && mounted) {
        await _showSnack('Canceled stale drone orders: $canceled');
      }
    }
  }

  Future<void> _replaceCanceledManagedOrder({
    required BingxFuturesApiCredentials credentials,
    required BingxManagedOrderProvenance provenance,
    required BingxFuturesLiveDecisionResult liveDecision,
    required String cancellationReasonCode,
    required Set<String> replacementLifecycleKeys,
  }) async {
    final cycleAtUtc = DateTime.now().toUtc().toIso8601String();
    final plan = _module.orderReplacement.plan(
      provenance: provenance,
      liveDecision: liveDecision,
      cancellationReasonCode: cancellationReasonCode,
      cycleAtUtc: cycleAtUtc,
    );
    await _module.uiLog.log(
      'bingx.exchange.replace.plan',
      'oldOrderId=${provenance.orderId} symbol=${provenance.symbol} '
          'status=${plan.status.name} reason=${plan.reasonCode} '
          'liveHash=${liveDecision.liveDecisionHashHex.substring(0, 12)}',
    );
    if (!plan.isReady) return;
    final peerHex = plan.hostArgs!['peer_hex']?.toString().trim() ?? '';
    final lifecycleKey =
        '$peerHex|${provenance.symbol.toUpperCase()}|${provenance.side}';
    if (!replacementLifecycleKeys.add(lifecycleKey)) {
      await _module.uiLog.log(
        'bingx.exchange.replace.skip',
        'oldOrderId=${provenance.orderId} symbol=${provenance.symbol} '
            'reason=replacement_lifecycle_duplicate key=$lifecycleKey',
      );
      return;
    }

    Map<String, dynamic>? replacementIntentResult;
    final runtime = await _module.orderReplacement.execute(
      provenance: provenance,
      liveDecision: liveDecision,
      cancellationReasonCode: cancellationReasonCode,
      cycleAtUtc: cycleAtUtc,
      prepareIntent: (hostArgs) async {
        final response = await _module.pluginHostApi
            .executeWithRuntimeHook(
              PluginHostApiRequest(
                schemaVersion: pluginHostApiSchemaVersion,
                pluginId: bingxFuturesTradingPluginId,
                method: placeBingxFuturesOrderIntentMethod,
                args: hostArgs,
              ),
            )
            .timeout(_TradingDroneScreenState._hostIntentTimeout);
        replacementIntentResult = response.result;
        return response;
      },
      evaluateRisk: (payload, rawIntentResult) {
        return _evaluateExecutionRisk(
          payload: payload,
          rawIntentResult: rawIntentResult,
        );
      },
      executeOrder: (payload, testOrder) async {
        final rawIntentResult = replacementIntentResult;
        if (rawIntentResult == null) return null;
        final execution = await _module.executionUseCase.execute(
          screen: 'trading_drone_replacement',
          rawIntentResult: rawIntentResult,
          credentials: credentials,
          riskPolicy: _TradingDroneScreenState._executionRiskPolicy,
          fallbackEquityQuote:
              _TradingDroneScreenState._fallbackRiskEquityQuote,
          testOrder: testOrder,
          preparedDecision: liveDecision,
          refreshDecision:
              () => _computeLiveDecision(
                symbol: payload.symbol,
                peerHex: '',
                silent: true,
                forceConsensusSignable: true,
                zoneEvaluationSide: payload.side,
              ),
        );
        return execution.queuedExecution;
      },
    );
    final response = runtime.hostResponse;
    await _module.uiLog.log(
      'bingx.exchange.replace.intent',
      'oldOrderId=${provenance.orderId} runtime=${runtime.status.name} '
          'status=${response?.status.name ?? "-"} '
          'source=${response?.executionSource ?? "-"} '
          'code=${response?.errorCode ?? "-"}',
    );
    final riskDecision = runtime.riskDecision;
    if (runtime.status == BingxFuturesReplacementRuntimeStatus.riskBlocked ||
        runtime.status ==
            BingxFuturesReplacementRuntimeStatus.riskUnavailable) {
      await _module.uiLog.log(
        'bingx.exchange.replace.risk_blocked',
        'oldOrderId=${provenance.orderId} '
            'code=${riskDecision?.reasonCode ?? "risk_unavailable"}',
      );
    }
    final payload = runtime.payload;
    final queued = runtime.queuedExecution;
    final result = response?.result;
    if (payload == null ||
        queued == null ||
        riskDecision == null ||
        result == null) {
      return;
    }

    final executionEnvelope = _module.observability.buildExecutionEnvelope(
      screen: 'trading_drone_replacement',
      symbol: payload.symbol,
      side: payload.side,
      orderType: payload.orderType,
      idempotencyKey: queued.idempotencyKey,
      attempts: queued.attempts,
      fromIdempotentCache: queued.fromIdempotentCache,
      isSuccess: queued.execution.isSuccess,
      httpStatusCode: queued.execution.httpStatusCode,
      exchangeCode: queued.execution.exchangeCode,
      endpointPath: queued.execution.endpointPath,
      orderId: queued.execution.orderId,
      intentHashHex: payload.intentHashHex,
      riskDecisionCode: riskDecision.reasonCode,
      riskDecisionHashHex: riskDecision.decisionHashHex,
      marketSnapshotHashHex:
          result['market_snapshot_hash_hex']?.toString().trim(),
      featureHashHex: result['feature_hash_hex']?.toString().trim(),
      tvhDecisionHashHex: result['tvh_decision_hash_hex']?.toString().trim(),
      liveDecisionHashHex: result['live_decision_hash_hex']?.toString().trim(),
    );
    await _module.uiLog.log(
      'bingx.exchange.replace.execute',
      'oldOrderId=${provenance.orderId} '
          'success=${queued.execution.isSuccess} '
          'newOrderId=${queued.execution.orderId ?? "-"} '
          'attempts=${queued.attempts} code=${queued.execution.exchangeCode}',
    );
    await _module.uiLog.log(
      'drone.execution.envelope',
      'hash=${executionEnvelope.envelopeHashHex} '
          'kind=execution screen=trading_drone_replacement',
    );
    if (!queued.execution.isSuccess) return;

    final newOrderId = queued.execution.orderId?.trim();
    if (newOrderId == null || newOrderId.isEmpty) {
      await _module.uiLog.log(
        'bingx.exchange.replace.skip',
        'oldOrderId=${provenance.orderId} '
            'reason=replacement_receipt_missing_order_id',
      );
      return;
    }
    _registerManagedOrderId(
      newOrderId,
      symbol: payload.symbol,
      provenance: _buildManagedOrderProvenance(
        orderId: newOrderId,
        payload: payload,
        result: result,
        testOrder: provenance.testOrder,
        credentials: credentials,
      ),
    );
    _startOpenOrdersAutoTracking(symbol: payload.symbol, orderId: newOrderId);
    await _module.uiLog.log(
      'bingx.exchange.replace.complete',
      'oldOrderId=${provenance.orderId} newOrderId=$newOrderId '
          'intentHash=${_shortHash(payload.intentHashHex)}',
    );
  }

  String _shortHash(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return '-';
    return normalized.length <= 12 ? normalized : normalized.substring(0, 12);
  }

  Future<void> _cancelOrder({BingxFuturesOpenOrder? order}) async {
    if (_cancelingOrder) return;
    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return;
    }
    final symbol = order?.symbol.trim() ?? _symbolController.text.trim();
    if (symbol.isEmpty) {
      await _showSnack('Symbol is required');
      return;
    }
    final orderId =
        order?.orderId.trim() ?? _cancelOrderIdController.text.trim();
    if (orderId.isEmpty) {
      await _showSnack('Order ID is required');
      return;
    }

    _updateState(() {
      _cancelingOrder = true;
    });
    try {
      final result = await _module.exchangeService.cancelOrder(
        credentials: credentials,
        symbol: symbol,
        orderId: orderId,
      );
      final message = result.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _module.uiLog.log(
        'bingx.exchange.cancel_order',
        'symbol=${result.symbol} requestOrderId=${result.requestedOrderId} '
            'canceledOrderId=${result.canceledOrderId ?? "-"} '
            'success=${result.isSuccess} http=${result.httpStatusCode} '
            'code=${result.exchangeCode} endpoint=${result.endpointPath} msg=$message',
      );
      if (!mounted) return;
      _updateState(() {
        _lastCancelOrder = result;
        if (result.isSuccess) {
          final canceled = result.canceledOrderId ?? result.requestedOrderId;
          _managedOrderIds.remove(canceled);
          _managedOrderSymbols.remove(canceled);
          _managedOrderProvenance.remove(canceled);
          _managedOrderLifecycleRevision += 1;
          _openOrders =
              _openOrders.where((order) => order.orderId != canceled).toList();
        }
      });
      if (result.isSuccess) {
        await _persistOpenOrdersTrackingState(source: 'cancel_order');
      }
      await _showSnack(
        result.isSuccess
            ? 'Order canceled: ${result.canceledOrderId ?? result.requestedOrderId}'
            : 'Cancel failed: ${result.exchangeCode}',
        seconds: result.isSuccess ? 2 : 4,
      );
      if (result.isSuccess) {
        await _fetchOpenOrders(silent: true);
      }
    } catch (error) {
      await _module.uiLog.log('bingx.exchange.cancel_order.error', '$error');
      await _showSnack('Cancel order failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        _updateState(() {
          _cancelingOrder = false;
        });
      }
    }
  }
}
