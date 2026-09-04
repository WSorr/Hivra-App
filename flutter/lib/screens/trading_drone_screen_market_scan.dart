part of 'trading_drone_screen.dart';

extension _TradingDroneMarketScan on _TradingDroneScreenState {
  Future<void> _loadPerpetualSymbols({required bool silent}) async {
    if (_loadingPerpSymbols) return;
    if (mounted) {
      _updateState(() {
        _loadingPerpSymbols = true;
      });
    } else {
      _loadingPerpSymbols = true;
    }
    try {
      final result = await _module.exchangeService.getPerpetualSymbols();
      await _module.uiLog.log(
        'bingx.symbols.perp',
        'success=${result.isSuccess} http=${result.httpStatusCode} '
            'code=${result.exchangeCode} count=${result.symbols.length} '
            'endpoint=${result.endpointPath}',
      );
      if (!result.isSuccess || result.symbols.isEmpty) {
        if (!silent) {
          await _showSnack(
            'Perp symbols failed: ${result.exchangeCode}',
            seconds: 3,
          );
        }
        return;
      }
      final merged = <String>{
        ...result.symbols,
        ..._TradingDroneScreenState._shortBreakdownSymbols,
      };
      final sorted = merged.toList()..sort();
      if (!mounted) return;
      _updateState(() {
        _availablePerpSymbols = List<String>.unmodifiable(sorted);
      });
      if (!silent) {
        await _showSnack('Perp symbols loaded: ${sorted.length}');
      }
    } catch (error) {
      await _module.uiLog.log('bingx.symbols.perp.error', '$error');
      if (!silent) {
        await _showSnack('Perp symbols failed: $error', seconds: 3);
      }
    } finally {
      if (mounted) {
        _updateState(() {
          _loadingPerpSymbols = false;
        });
      } else {
        _loadingPerpSymbols = false;
      }
    }
  }

  Future<void> _openPerpetualSymbolPicker() async {
    if (_availablePerpSymbols.isEmpty) {
      await _loadPerpetualSymbols(silent: false);
      if (!mounted) return;
      if (_availablePerpSymbols.isEmpty) return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _availablePerpSymbols
                .where((symbol) {
                  if (query.isEmpty) return true;
                  return symbol.toLowerCase().contains(query.toLowerCase());
                })
                .toList(growable: false);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Search perpetual symbol',
                        hintText: 'BTC-USDT',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          query = value.trim();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 420,
                      child:
                          filtered.isEmpty
                              ? const Center(
                                child: Text(
                                  'No symbols',
                                  style: TextStyle(color: Color(0xFF97A3B5)),
                                ),
                              )
                              : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final symbol = filtered[index];
                                  return ListTile(
                                    title: Text(symbol),
                                    onTap:
                                        () => Navigator.of(
                                          sheetContext,
                                        ).pop(symbol),
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    _updateState(() {
      _symbolController.text = selected;
      _displayedZoneDecision = null;
      _lastIntentResponse = null;
      _lastPreparedLiveDecision = null;
      _intentBlockingMessage = null;
    });
    await _module.uiLog.log(
      'bingx.symbols.select',
      'symbol=$selected source=picker',
    );
    await _maybeRetargetOpenOrdersTracking(
      symbol: selected,
      source: 'picker',
      force: true,
    );
  }

  Future<void> _scanSignalWatchlist() async {
    if (_scanningSignals) return;
    final currentSymbol = _symbolController.text.trim().toUpperCase();
    if (_signalScanScope == _TradingDroneScreenState._signalScanScopeAllPerps &&
        _availablePerpSymbols.isEmpty) {
      await _loadPerpetualSymbols(silent: false);
      if (!mounted) return;
    }
    final rawSymbols = _signalScanSymbols(currentSymbol);
    if (rawSymbols.isEmpty) {
      await _showSnack('No symbols to scan');
      return;
    }
    if (mounted) {
      _updateState(() {
        _scanningSignals = true;
      });
    } else {
      _scanningSignals = true;
    }
    try {
      await _module.uiLog.log(
        'bingx.signal.scan.start',
        'scope=$_signalScanScope symbols=${rawSymbols.length} '
            'prefilter=5m_volume_growth',
      );
      final scanObservedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final symbols = await _filterVolumeGrowthSymbols(
        rawSymbols,
        observedAtMs: scanObservedAtMs,
      );
      if (symbols.isEmpty) {
        await _module.uiLog.log(
          'bingx.signal.scan.empty',
          'scope=$_signalScanScope source_symbols=${rawSymbols.length} '
              'prefilter=5m_volume_growth observed_at_ms=$scanObservedAtMs',
        );
        await _showSnack(
          'Signal scan: no symbols with rising 5m volume',
          seconds: 3,
        );
        return;
      }
      final candidates = <BingxFuturesSignalRankCandidate>[];
      var skipped = 0;
      for (final symbol in symbols) {
        BingxFuturesLiveDecisionResult? decision;
        try {
          decision = await _computeLiveDecision(symbol: symbol, silent: true);
        } catch (error) {
          skipped += 1;
          await _module.uiLog.log(
            'bingx.signal.rank.candidate_error',
            'symbol=$symbol error=$error',
          );
          continue;
        }
        if (decision == null) continue;
        candidates.add(
          BingxFuturesSignalRankCandidate(symbol: symbol, decision: decision),
        );
      }
      if (candidates.isEmpty) {
        await _showSnack('Signal scan failed: no live decisions', seconds: 3);
        return;
      }
      final ranked = await _module.signalRankUseCase.execute(
        BingxFuturesSignalRankCommand(candidates: candidates),
      );
      if (!ranked.isSuccess) {
        await _module.uiLog.log(
          'bingx.signal.rank.rejected',
          'status=${ranked.response.status.name} code=${ranked.response.errorCode ?? "-"} '
              'message=${ranked.response.errorMessage ?? "-"}',
        );
        await _showSnack(
          'Signal rank failed: ${ranked.response.errorCode ?? ranked.response.status.name}',
          seconds: 4,
        );
        return;
      }
      if (!mounted) return;
      _updateState(() {
        _signalRankEntries = ranked.entries;
        _signalScanCompletedAtUtc = DateTime.now().toUtc();
        _signalDecisionByHash = <String, BingxFuturesLiveDecisionResult>{
          for (final candidate in candidates)
            candidate.decision.liveDecisionHashHex: candidate.decision,
        };
        _side = tradingPreferredSideForCycle(
          symbol: currentSymbol,
          currentSide: _side,
          rankedEntries: ranked.entries,
        );
        _zoneSide = tradingZoneSideForOrderSide(_side);
        _signalRankExpanded = true;
      });
      final top = ranked.entries.isEmpty ? null : ranked.entries.first;
      await _module.uiLog.log(
        'bingx.signal.rank',
        'scope=$_signalScanScope source_symbols=${rawSymbols.length} '
            'volume_growth_symbols=${symbols.length} '
            'candidates=${candidates.length} '
            'skipped=$skipped '
            'entries=${ranked.entries.length} scan_hash=${_shortHash(ranked.scanHashHex)} '
            'top=${top == null ? "-" : "${top.symbol}:${top.bucket}:${top.score}"}',
      );
      await _showSnack(
        ranked.entries.any((entry) => entry.bucket == 'ready')
            ? 'Signal scan complete: ready found'
            : skipped > 0
            ? 'Signal scan partial: no ready signals, skipped $skipped'
            : 'Signal scan complete: no ready signals',
        seconds: 2,
      );
    } catch (error) {
      await _module.uiLog.log('bingx.signal.rank.error', '$error');
      if (mounted) {
        await _showSnack('Signal scan failed: $error', seconds: 3);
      }
    } finally {
      if (mounted) {
        _updateState(() {
          _scanningSignals = false;
        });
      } else {
        _scanningSignals = false;
      }
    }
  }

  List<String> _signalScanSymbols(String currentSymbol) {
    final source =
        _signalScanScope == _TradingDroneScreenState._signalScanScopeAllPerps
            ? _availablePerpSymbols
            : _TradingDroneScreenState._shortBreakdownSymbols;
    final symbols =
        <String>{
              ...source.map((symbol) => symbol.trim().toUpperCase()),
              if (currentSymbol.isNotEmpty) currentSymbol,
            }
            .where(
              (symbol) =>
                  symbol.isNotEmpty && _isNormalCryptoPerpSymbol(symbol),
            )
            .toList()
          ..sort();
    return symbols;
  }

  bool _isNormalCryptoPerpSymbol(String symbol) {
    final parts = symbol.trim().toUpperCase().split('-');
    if (parts.length != 2) return false;
    final base = parts[0];
    final quote = parts[1];
    if (quote != 'USDT' && quote != 'USDC') return false;
    if (!RegExp(r'^[A-Z][A-Z0-9]{1,14}$').hasMatch(base)) return false;
    if (base.startsWith('NC')) return false;
    if (RegExp(r'^\d').hasMatch(base)) return false;
    return true;
  }

  Future<List<String>> _filterVolumeGrowthSymbols(
    List<String> symbols, {
    required int observedAtMs,
  }) async {
    if (_signalScanScope == _TradingDroneScreenState._signalScanScopeCore) {
      await _module.uiLog.log(
        'bingx.signal.volume_prefilter.skip',
        'scope=$_signalScanScope source=${symbols.length} reason=core_watchlist',
      );
      return symbols;
    }
    final tickerFiltered = await _prefilterLiquidTickerSymbols(symbols);
    final accepted = <String>[];
    var insufficient = 0;
    var flatOrFalling = 0;
    var failed = 0;
    for (final symbol in tickerFiltered) {
      try {
        final result = await _module.exchangeService.getPublicKlines(
          symbol: symbol,
          interval: '5m',
          limit: _TradingDroneScreenState._signalVolumeGrowthKlineLimit,
        );
        if (!result.isSuccess || result.klines.length < 3) {
          insufficient += 1;
          continue;
        }
        final grows = _module.volumeGrowthFilter.hasStrictlyRisingClosedVolume(
          klines: result.klines,
          observedAtMs: observedAtMs,
        );
        if (grows) {
          accepted.add(symbol);
        } else {
          flatOrFalling += 1;
        }
      } catch (error) {
        failed += 1;
        await _module.uiLog.log(
          'bingx.signal.volume_prefilter.error',
          'symbol=$symbol error=$error',
        );
      }
    }
    await _module.uiLog.log(
      'bingx.signal.volume_prefilter',
      'scope=$_signalScanScope source=${symbols.length} '
          'ticker_filtered=${tickerFiltered.length} accepted=${accepted.length} '
          'flat_or_falling=$flatOrFalling insufficient=$insufficient failed=$failed '
          'observed_at_ms=$observedAtMs candles=closed',
    );
    return accepted;
  }

  Future<List<String>> _prefilterLiquidTickerSymbols(
    List<String> symbols,
  ) async {
    if (_signalScanScope != _TradingDroneScreenState._signalScanScopeAllPerps ||
        symbols.length <=
            _TradingDroneScreenState._signalTickerPrefilterLimit) {
      return symbols;
    }
    try {
      final tickers = await _module.exchangeService.getPublicTickers();
      if (!tickers.isSuccess || tickers.tickers.isEmpty) {
        await _module.uiLog.log(
          'bingx.signal.ticker_prefilter.skip',
          'reason=ticker_unavailable code=${tickers.exchangeCode} '
              'message=${tickers.exchangeMessage}',
        );
        return symbols;
      }
      final allowed = symbols.toSet();
      final currentSymbol = _symbolController.text.trim().toUpperCase();
      final selected =
          tickers.tickers
              .where(
                (ticker) =>
                    allowed.contains(ticker.symbol) &&
                    _isNormalCryptoPerpSymbol(ticker.symbol),
              )
              .take(_TradingDroneScreenState._signalTickerPrefilterLimit)
              .map((ticker) => ticker.symbol)
              .toSet();
      if (currentSymbol.isNotEmpty && allowed.contains(currentSymbol)) {
        selected.add(currentSymbol);
      }
      final out = selected.toList()..sort();
      await _module.uiLog.log(
        'bingx.signal.ticker_prefilter',
        'source=${symbols.length} selected=${out.length} '
            'limit=$_TradingDroneScreenState._signalTickerPrefilterLimit sort=quote_volume_desc',
      );
      return out;
    } catch (error) {
      await _module.uiLog.log('bingx.signal.ticker_prefilter.error', '$error');
      return symbols;
    }
  }

  String _signalScanScopeLabel() {
    if (_signalScanScope == _TradingDroneScreenState._signalScanScopeAllPerps) {
      final count = _availablePerpSymbols.length;
      return count > 0
          ? 'All Perps ($count, top $_TradingDroneScreenState._signalTickerPrefilterLimit volume)'
          : 'All Perps';
    }
    return 'Core Watchlist (${_TradingDroneScreenState._shortBreakdownSymbols.length})';
  }

  Future<void> _applySignalRankEntry(BingxFuturesSignalRankEntry entry) async {
    if (!mounted) return;
    final decision = _signalDecisionByHash[entry.liveDecisionHashHex];
    _updateState(() {
      _symbolController.text = entry.symbol;
      _displayedZoneDecision = decision;
      _lastIntentResponse = null;
      _lastPreparedLiveDecision = null;
      _intentBlockingMessage = null;
      if (entry.side != null) {
        _side = entry.side!;
        _zoneSide = tradingZoneSideForOrderSide(entry.side!);
      }
      if (decision?.canPrepareIntent == true &&
          entry.zoneLowDecimal != null && entry.zoneHighDecimal != null) {
        _zoneLowController.text = entry.zoneLowDecimal!;
        _zoneHighController.text = entry.zoneHighDecimal!;
      } else {
        _zoneLowController.clear();
        _zoneHighController.clear();
      }
      _signalRankExpanded = false;
    });
    await _module.uiLog.log(
      'bingx.signal.rank.select',
      'symbol=${entry.symbol} bucket=${entry.bucket} score=${entry.score} '
          'side=${entry.side ?? "-"} live_hash=${_shortHash(entry.liveDecisionHashHex)}',
    );
    await _maybeRetargetOpenOrdersTracking(
      symbol: entry.symbol,
      source: 'signal_rank',
      force: true,
    );
  }

  String _playbookQtyForSymbol(String symbol) {
    return switch (symbol.toUpperCase()) {
      'BTC-USDT' => '0.001',
      'ETH-USDT' => '0.01',
      'SOL-USDT' => '0.10',
      'BNB-USDT' => '0.01',
      'XRP-USDT' => '10',
      'DOGE-USDT' => '50',
      _ => '0.01',
    };
  }

  Future<void> _applyShortBreakdownPlaybook({required String symbol}) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) return;
    if (mounted) {
      _updateState(() {
        _symbolController.text = normalizedSymbol;
        _displayedZoneDecision = null;
        _lastIntentResponse = null;
        _lastPreparedLiveDecision = null;
        _intentBlockingMessage = null;
        _quantityController.text = _playbookQtyForSymbol(normalizedSymbol);
        _side = 'sell';
        _zoneSide = 'sellside';
        _strategyTagController.text = 'tvh_short_breakdown_v1';
        _zoneLowController.clear();
        _zoneHighController.clear();
        _triggerPriceController.clear();
        _stopLossController.clear();
        _takeProfitController.clear();
      });
    }
    await _module.uiLog.log(
      'bingx.playbook.apply',
      'name=short_breakdown_v1 symbol=$normalizedSymbol side=sell mode=zone_pending',
    );
    await _maybeRetargetOpenOrdersTracking(
      symbol: normalizedSymbol,
      source: 'playbook',
      force: true,
    );
    await _showSnack('Playbook applied: short breakdown · $normalizedSymbol');
  }
}
