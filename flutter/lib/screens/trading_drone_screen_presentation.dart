part of 'trading_drone_screen.dart';

extension _TradingDronePresentation on _TradingDroneScreenState {
  Widget _statusChip(String label, {Color? accent}) {
    final color = accent ?? const Color(0xFFAEB9C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent == null ? const Color(0xFF10161D) : color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              accent == null ? const Color(0xFF29313D) : color.withAlpha(120),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _openOrderCard(BingxFuturesOpenOrder order) {
    final isManaged = _managedOrderIds.contains(order.orderId);
    final badgeColor =
        isManaged ? const Color(0xFF75D98A) : const Color(0xFFFFC76A);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1322),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D3550), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order.symbol} · ${order.side} · ${order.orderType}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE6EBFF),
                  ),
                ),
              ),
              _statusChip(
                isManaged ? 'Drone' : 'Exchange only',
                accent: badgeColor,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'id ${order.orderId}',
            style: const TextStyle(
              color: Color(0xFF9FAAC0),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'status ${order.status.isEmpty ? "-" : order.status} · '
            'price ${order.priceDecimal ?? "-"} · '
            'trigger ${order.triggerPriceDecimal ?? "-"} · '
            'qty ${order.quantityDecimal ?? "-"}',
            style: const TextStyle(color: Color(0xFFC4CCE0)),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  'created ${_formatOrderTime(order.createdAtMs)}',
                  style: const TextStyle(color: Color(0xFF8D97AE)),
                ),
              ),
              TextButton.icon(
                onPressed:
                    _cancelingOrder ? null : () => _cancelOrder(order: order),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121821),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B3846)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF97A3B5), height: 1.35),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Color _signalBucketColor(String bucket) {
    return switch (bucket) {
      'ready' => Colors.green,
      'near' => Colors.amber,
      'blocked' => Colors.orange,
      'no_signal' => const Color(0xFF97A3B5),
      _ => Colors.redAccent,
    };
  }

  String _signalBucketLabel(String bucket) {
    return switch (bucket) {
      'ready' => 'READY',
      'near' => 'NEAR',
      'blocked' => 'BLOCKED',
      'no_signal' => 'NO SIGNAL',
      _ => 'ERROR',
    };
  }

  Widget _signalRankList() {
    if (_signalRankEntries.isEmpty) {
      return const Text(
        'No scan yet. Host computes live summaries; plugin ranks signals.',
        style: TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
      );
    }
    final top = _signalRankEntries.first;
    if (!_signalRankExpanded) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _updateState(() => _signalRankExpanded = true),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F141C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF263343)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: _signalBucketColor(top.bucket),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Top ${top.symbol} · ${_signalBucketLabel(top.bucket)} · score ${top.score}',
                  style: const TextStyle(
                    color: Color(0xFFCAD2E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                'Show',
                style: TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in _signalRankEntries)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F141C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF263343)),
            ),
            child: ListTile(
              dense: true,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.symbol,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _signalBucketColor(
                        entry.bucket,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _signalBucketLabel(entry.bucket),
                      style: TextStyle(
                        color: _signalBucketColor(entry.bucket),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                'score ${entry.score} · side ${entry.side ?? "-"} · '
                'zone ${entry.zoneLowDecimal ?? "-"}-${entry.zoneHighDecimal ?? "-"} · '
                'gate ${entry.trendGateCode}'
                '${entry.failedReasonCodes.isEmpty ? "" : " · failed ${entry.failedReasonCodes.join(",")}"}',
                style: const TextStyle(color: Color(0xFF97A3B5)),
              ),
              onTap: () => _applySignalRankEntry(entry),
            ),
          ),
      ],
    );
  }

  Widget _buildScreen(BuildContext context) {
    final selectedSymbol = _symbolController.text.trim().toUpperCase();
    final nowUtc = DateTime.now().toUtc();
    final hasExecutableIntent = tradingHasExecutableIntent(
      status: _lastIntentResponse?.status,
      hasResult: _lastIntentResponse?.result != null,
      mandate: _tradingMandate,
      droneEnabled: _droneEnabled,
      selectedSymbol: selectedSymbol,
      selectedMaxNotional: _maxNotionalUsdtController.text,
      selectedMaxEffects: _maxEffects,
      testOrder: _useTestOrderEndpoint,
      nowUtc: nowUtc,
    );
    final mandateSelectionNotice = tradingMandateSelectionNotice(
      mandate: _tradingMandate,
      droneEnabled: _droneEnabled,
      selectedSymbol: selectedSymbol,
      selectedMaxNotional: _maxNotionalUsdtController.text,
      selectedMaxEffects: _maxEffects,
      testOrder: _useTestOrderEndpoint,
      nowUtc: nowUtc,
    );
    final tradingControlSubtitle =
        !_tradingControlLoaded || _savingTradingControl
            ? 'Loading Capsule trading control.'
            : mandateSelectionNotice ??
                (_droneEnabled
                    ? 'Strategy can prepare and execute orders.'
                    : 'Paused. New strategy runs are blocked.');
    final shortIntentHash =
        _lastIntentResponse?.result?['intent_hash_hex']?.toString() ?? '';
    final intentHashLabel =
        shortIntentHash.isEmpty
            ? 'none'
            : (shortIntentHash.length > 12
                ? '${shortIntentHash.substring(0, 12)}..'
                : shortIntentHash);

    return Scaffold(
      appBar: AppBar(title: const Text('Trading Drone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _panel(
            title: 'Intent Builder',
            subtitle: 'Deterministic pending futures intent for plugin host.',
            children: [
              const Text(
                'Playbook · Short Breakdown v1',
                style: TextStyle(
                  color: Color(0xFF97A3B5),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final symbol
                      in _TradingDroneScreenState._shortBreakdownSymbols)
                    ActionChip(
                      label: Text(symbol),
                      onPressed:
                          _runningIntent
                              ? null
                              : () =>
                                  _applyShortBreakdownPlaybook(symbol: symbol),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 320,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _symbolController,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Perp Symbol',
                              hintText: 'BTC-USDT',
                              filled: true,
                              fillColor: const Color(0xFF0F141C),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onSubmitted: (value) {
                              final symbol = value.trim().toUpperCase();
                              if (symbol.isEmpty) return;
                              _updateState(() {
                                _symbolController.text = symbol;
                                _displayedZoneDecision = null;
                                _lastIntentResponse = null;
                                _lastPreparedLiveDecision = null;
                                _intentBlockingMessage = null;
                              });
                              unawaited(
                                _maybeRetargetOpenOrdersTracking(
                                  symbol: symbol,
                                  source: 'manual_input',
                                  force: true,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed:
                              _runningIntent
                                  ? null
                                  : _loadingPerpSymbols
                                  ? null
                                  : _openPerpetualSymbolPicker,
                          icon:
                              _loadingPerpSymbols
                                  ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.tune_rounded),
                          label: const Text('Perp'),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed:
                              _loadingPerpSymbols
                                  ? null
                                  : () => _loadPerpetualSymbols(silent: false),
                          tooltip: 'Refresh symbols',
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _maxNotionalUsdtController,
                      onChanged: (_) => _updateState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Max Notional (USDT)',
                        hintText: '100',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _availablePerpSymbols.isEmpty
                    ? 'Perp symbols: not loaded (manual input available)'
                    : 'Perp symbols loaded: ${_availablePerpSymbols.length}',
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: _signalScanScope,
                    dropdownColor: const Color(0xFF121821),
                    items: const [
                      DropdownMenuItem<String>(
                        value: _TradingDroneScreenState._signalScanScopeCore,
                        child: Text('Core Watchlist'),
                      ),
                      DropdownMenuItem<String>(
                        value:
                            _TradingDroneScreenState._signalScanScopeAllPerps,
                        child: Text('All Perps'),
                      ),
                    ],
                    onChanged:
                        _scanningSignals
                            ? null
                            : (value) {
                              if (value == null) return;
                              _updateState(() {
                                _signalScanScope = value;
                                _signalRankEntries =
                                    const <BingxFuturesSignalRankEntry>[];
                                _signalScanCompletedAtUtc = null;
                                _signalDecisionByHash =
                                    const <
                                      String,
                                      BingxFuturesLiveDecisionResult
                                    >{};
                                _signalRankExpanded = true;
                              });
                            },
                  ),
                  FilledButton.icon(
                    onPressed:
                        _runningIntent || _scanningSignals
                            ? null
                            : _scanSignalWatchlist,
                    icon:
                        _scanningSignals
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Icon(
                              _signalRankEntries.isEmpty
                                  ? Icons.radar_rounded
                                  : Icons.refresh_rounded,
                            ),
                    label: Text(
                      tradingSignalScanActionLabel(scanning: _scanningSignals),
                    ),
                  ),
                  Text(
                    _signalRankEntries.isEmpty
                        ? '${_signalScanScopeLabel()} · not ranked'
                        : 'Ranked ${_signalRankEntries.length}',
                    style: const TextStyle(
                      color: Color(0xFF97A3B5),
                      fontSize: 12,
                    ),
                  ),
                  if (_signalRankEntries.isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: () {
                        _updateState(() {
                          _signalRankExpanded = !_signalRankExpanded;
                        });
                      },
                      icon: Icon(
                        _signalRankExpanded
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                        size: 16,
                      ),
                      label: Text(_signalRankExpanded ? 'Collapse' : 'Show'),
                    ),
                  ],
                ],
              ),
              if (_signalScanCompletedAtUtc != null) ...[
                const SizedBox(height: 8),
                Text(
                  tradingSignalSnapshotLabel(_signalScanCompletedAtUtc!),
                  style: const TextStyle(
                    color: Color(0xFF97A3B5),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _signalRankList(),
              const SizedBox(height: 8),
              Text(
                'Estimated order quantity: ${_quantityController.text}',
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              SwitchListTile.adaptive(
                value: _droneEnabled,
                onChanged:
                    _runningIntent ||
                            !_tradingControlLoaded ||
                            _savingTradingControl
                        ? null
                        : (value) {
                          unawaited(_changeDroneEnabled(value));
                        },
                title: const Text('Drone enabled'),
                subtitle: Text(
                  tradingControlSubtitle,
                  style: const TextStyle(color: Color(0xFF97A3B5)),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (mandateSelectionNotice != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed:
                        _runningIntent || _savingTradingControl
                            ? null
                            : () => unawaited(_changeDroneEnabled(true)),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text('Re-authorize $selectedSymbol'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Auto risk',
                    style: TextStyle(
                      color: Color(0xFF97A3B5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  DropdownButton<double>(
                    value: _stopLossPercent,
                    dropdownColor: const Color(0xFF121821),
                    items: _TradingDroneScreenState._stopLossPercentOptions
                        .map(
                          (value) => DropdownMenuItem<double>(
                            value: value,
                            child: Text('SL ${value.toStringAsFixed(0)}%'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged:
                        _runningIntent
                            ? null
                            : (value) {
                              if (value == null) return;
                              _updateState(() {
                                _stopLossPercent = value;
                              });
                              unawaited(
                                _persistOpenOrdersTrackingState(
                                  source: 'risk_settings_sl_change',
                                ),
                              );
                            },
                  ),
                  DropdownButton<double>(
                    value: _takeProfitRiskReward,
                    dropdownColor: const Color(0xFF121821),
                    items: _TradingDroneScreenState._takeProfitRiskRewardOptions
                        .map(
                          (value) => DropdownMenuItem<double>(
                            value: value,
                            child: Text(
                              'Min RR ${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged:
                        _runningIntent
                            ? null
                            : (value) {
                              if (value == null) return;
                              _updateState(() {
                                _takeProfitRiskReward = value;
                              });
                              unawaited(
                                _persistOpenOrdersTrackingState(
                                  source: 'risk_settings_rr_change',
                                ),
                              );
                            },
                  ),
                  DropdownButton<int>(
                    value: _maxEffects,
                    dropdownColor: const Color(0xFF121821),
                    items: tradingEffectBudgetOptions
                        .map(
                          (value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text(
                              '${tradingOrderBudgetLabel(value)} / 24h',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged:
                        _runningIntent || _savingTradingControl
                            ? null
                            : (value) {
                              if (value == null) return;
                              _updateState(() => _maxEffects = value);
                            },
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _runningIntent || _fittingMaxNotional
                            ? null
                            : _autoFitMaxNotionalToRisk,
                    icon:
                        _fittingMaxNotional
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.auto_fix_high_rounded),
                    label: Text(
                      _fittingMaxNotional ? 'Fitting' : 'Auto-fit Notional',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _zoneLowController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Pending Zone Low',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _zoneHighController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Pending Zone High',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _zoneLowController.text.isEmpty ||
                        _zoneHighController.text.isEmpty ||
                        _displayedZoneDecision == null
                    ? 'No prepared entry zone. Observed clusters are shown below.'
                    : formatBingxFuturesZoneEvidence(_displayedZoneDecision!),
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                formatBingxFuturesLiquidityObservation(_displayedZoneDecision),
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        _runningIntent ||
                                !_tradingControlLoaded ||
                                _savingTradingControl
                            ? null
                            : _runIntent,
                    icon:
                        _runningIntent
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.bolt_rounded),
                    label: Text(
                      _runningIntent ? _intentProgressLabel : 'Run Intent',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _runningIntent ||
                                _savingTradingControl ||
                                _exportingRemoteMandate ||
                                _exportingRemoteRevocation
                            ? null
                            : _manageRemoteRunners,
                    icon:
                        _exportingRemoteRevocation
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.dns_outlined),
                    label: Text(
                      _exportingRemoteRevocation
                          ? 'Loading Runner'
                          : 'Remote Runner',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _runningIntent ||
                                !_tradingControlLoaded ||
                                _savingTradingControl
                            ? null
                            : () =>
                                unawaited(_changeDroneEnabled(!_droneEnabled)),
                    icon: Icon(
                      _droneEnabled
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: Text(_droneEnabled ? 'Emergency Pause' : 'Resume'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _runningIntent ||
                                _savingTradingControl ||
                                _exportingRemoteMandate ||
                                !_droneEnabled
                            ? null
                            : _exportSignedRemoteDeterministicSession,
                    icon:
                        _exportingRemoteMandate
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.verified_user_outlined),
                    label: Text(
                      _exportingRemoteMandate
                          ? 'Signing VPS session'
                          : 'Authorize VPS Session',
                    ),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child:
                    _runningIntent
                        ? Container(
                          key: const ValueKey<String>('intent-progress'),
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF172033),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFF8DC2FF,
                              ).withValues(alpha: 0.45),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _intentProgressLabel,
                                style: const TextStyle(
                                  color: Color(0xFFC9DEFF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const LinearProgressIndicator(minHeight: 3),
                            ],
                          ),
                        )
                        : const SizedBox.shrink(
                          key: ValueKey<String>('intent-idle'),
                        ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(
                    'Status: ${tradingIntentStatusLabel(_lastIntentResponse?.status)}',
                  ),
                  _statusChip('Intent: $intentHashLabel'),
                  if (_lastIntentResponse?.errorCode != null &&
                      _lastIntentResponse!.errorCode!.trim().isNotEmpty)
                    _statusChip(
                      'Code: ${_lastIntentResponse!.errorCode!.trim()}',
                      accent: const Color(0xFFFF8A7A),
                    ),
                ],
              ),
              if (_intentBlockingMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A2418),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB86B35)),
                  ),
                  child: Text(
                    _intentBlockingMessage!,
                    style: const TextStyle(color: Color(0xFFFFC58F)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _panel(
            title: 'Exchange Execution',
            subtitle:
                'Credentialed execution queue with retry + idempotency cache.',
            children: [
              TradingDroneCredentialField(
                fieldKey: const ValueKey<String>('bingx-api-key-field'),
                controller: _apiKeyController,
                label: 'BingX API Key',
                showTooltip: 'Show API key',
                hideTooltip: 'Hide API key',
              ),
              const SizedBox(height: 10),
              TradingDroneCredentialField(
                fieldKey: const ValueKey<String>('bingx-api-secret-field'),
                controller: _apiSecretController,
                label: 'BingX API Secret',
                showTooltip: 'Show secret',
                hideTooltip: 'Hide secret',
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                value: _useTestOrderEndpoint,
                onChanged:
                    _executing
                        ? null
                        : (value) {
                          _updateState(() {
                            _useTestOrderEndpoint = value;
                            _lastIntentResponse = null;
                            _lastPreparedLiveDecision = null;
                            _intentBlockingMessage = null;
                          });
                        },
                title: Text(
                  _useTestOrderEndpoint
                      ? 'Simulation endpoint (no exchange order)'
                      : 'Live endpoint (creates exchange order)',
                ),
                subtitle: Text(
                  _useTestOrderEndpoint
                      ? 'Validates one exact request without placing it on BingX.'
                      : 'Places the exact authorized order on BingX.',
                  style: const TextStyle(color: Color(0xFF97A3B5)),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        _executing || !hasExecutableIntent
                            ? null
                            : _executeLastIntent,
                    icon:
                        _executing
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.send_rounded),
                    label: Text(
                      _executing
                          ? 'Sending to BingX'
                          : !hasExecutableIntent
                          ? 'Run Intent to Enable Order'
                          : _useTestOrderEndpoint
                          ? 'Send Test Order to BingX'
                          : 'Send Live Order to BingX',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _savingCredentials ? null : _saveCredentials,
                    icon:
                        _savingCredentials
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.key_rounded),
                    label: Text(
                      _savingCredentials ? 'Saving' : 'Save Credentials',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _fetchingOpenOrders ? null : () => _fetchOpenOrders(),
                    icon:
                        _fetchingOpenOrders
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.list_alt_rounded),
                    label: Text(
                      _fetchingOpenOrders ? 'Fetching Orders' : 'Open Orders',
                    ),
                  ),
                ],
              ),
              if (_isTrackingOpenOrders) ...[
                const SizedBox(height: 8),
                Text(
                  'Managed order tracking is active and stops automatically '
                  'when the order closes.',
                  style: const TextStyle(
                    color: Color(0xFF97A3B5),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _cancelOrderIdController,
                      decoration: InputDecoration(
                        labelText: 'Order ID to cancel',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _cancelingOrder ? null : _cancelOrder,
                    icon:
                        _cancelingOrder
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.cancel_presentation_rounded),
                    label: Text(_cancelingOrder ? 'Canceling' : 'Cancel Order'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_lastExecution != null)
                    _statusChip(
                      _lastExecution!.isSuccess
                          ? 'Order OK · ${_lastExecution!.exchangeCode}'
                          : 'Order FAIL · ${_lastExecution!.exchangeCode}',
                      accent:
                          _lastExecution!.isSuccess
                              ? const Color(0xFF75D98A)
                              : const Color(0xFFFF8A7A),
                    ),
                  if (_lastExecution != null)
                    _statusChip('HTTP ${_lastExecution!.httpStatusCode}'),
                  if (_lastExecutionAttempts > 0)
                    _statusChip('Attempts $_lastExecutionAttempts'),
                  if (_lastExecutionFromCache)
                    _statusChip(
                      'Idempotent cache',
                      accent: const Color(0xFFFFC76A),
                    ),
                  if (_lastOpenOrdersRead != null)
                    _statusChip(
                      'Open: ${_openOrders.length} · Drone: $_managedOpenOrderCount '
                      '(${_lastOpenOrdersRead!.exchangeCode})',
                      accent:
                          _lastOpenOrdersRead!.isSuccess
                              ? const Color(0xFF75D98A)
                              : const Color(0xFFFF8A7A),
                    ),
                  if (_isTrackingOpenOrders)
                    _statusChip(
                      'Tracking ${_trackedOrdersSymbol ?? "-"}'
                      '${_trackedOrderId == null ? '' : ' · id ${_trackedOrderId!}'}',
                      accent: const Color(0xFF8DC2FF),
                    ),
                  if (_lastCancelOrder != null)
                    _statusChip(
                      'Cancel: ${_lastCancelOrder!.exchangeCode}',
                      accent:
                          _lastCancelOrder!.isSuccess
                              ? const Color(0xFF75D98A)
                              : const Color(0xFFFF8A7A),
                    ),
                ],
              ),
              if (_openOrders.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Open Exchange Orders',
                    style: TextStyle(
                      color: Color(0xFF9FAAC0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final order in _openOrders.take(12)) _openOrderCard(order),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
