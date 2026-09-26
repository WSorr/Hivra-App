part of 'trading_drone_screen.dart';

@visibleForTesting
bool tradingRemoteRunnerProfileIsCompatible({
  required BingxFuturesRemoteRunnerProfile profile,
  required String accountBindingHashHex,
}) =>
    profile.accountBindingHashHex == accountBindingHashHex &&
    profile.runnerBuildId ==
        BingxFuturesRemoteMandateAdmission.deterministicRunnerBuildId;

@visibleForTesting
bool tradingRemoteRunnerMayHoldAuthority({
  required bool configured,
  required String? statusWire,
}) {
  if (!configured) return false;
  final fields = _tradingRemoteRunnerStatusFields(statusWire ?? '');
  if (fields == null) return true;
  final sessionState = fields['session_state'];
  if ({'absent', 'completed', 'stopped', 'expired'}.contains(sessionState) &&
      fields['active'] == 'inactive') {
    return false;
  }
  return true;
}

@visibleForTesting
bool tradingRemoteRunnerStatusMatchesSession({
  required String statusWire,
  required BingxFuturesRemoteMandateAdmission? session,
}) {
  final fields = _tradingRemoteRunnerStatusFields(statusWire);
  return fields != null &&
      session != null &&
      fields['session_operation_id'] == session.operationId;
}

@visibleForTesting
String? tradingRemoteRunnerSessionOperationId(String statusWire) =>
    _tradingRemoteRunnerStatusFields(statusWire)?['session_operation_id'];

@visibleForTesting
BingxFuturesRemoteMandateAdmission? tradingRemoteRunnerCurrentSession({
  required String statusWire,
  required BingxFuturesRemoteMandateAdmission? retainedSession,
}) {
  final fields = _tradingRemoteRunnerStatusFields(statusWire);
  if (fields == null || fields['session_state'] != 'active') return null;
  return tradingRemoteRunnerStatusMatchesSession(
        statusWire: statusWire,
        session: retainedSession,
      )
      ? retainedSession
      : null;
}

@visibleForTesting
String? tradingRemoteSessionStopLossNotice({
  required double stopLossPercent,
  required bool leverageVerified,
  required int? longLeverage,
  required int? shortLeverage,
  required double? nominalStopLossLimitPercent,
}) {
  if (!leverageVerified || nominalStopLossLimitPercent == null) {
    return 'BingX leverage could not be verified. Refresh account access before authorizing the VPS session.';
  }
  if (!stopLossPercent.isFinite ||
      stopLossPercent <= 0 ||
      stopLossPercent >= nominalStopLossLimitPercent) {
    return 'SL ${stopLossPercent.toStringAsFixed(1)}% is incompatible with '
        'BingX leverage (long ${longLeverage}x, '
        'short ${shortLeverage}x). Choose SL below '
        '${nominalStopLossLimitPercent.toStringAsFixed(2)}% or reduce exchange leverage.';
  }
  return null;
}

extension _TradingDroneRemoteSession on _TradingDroneScreenState {
  Future<void> _emergencyPauseTrading() async {
    if (_savingTradingControl || _exportingRemoteRevocation) return;
    final remoteMayHoldAuthority = tradingRemoteRunnerMayHoldAuthority(
      configured: _remoteRunnerConfigured,
      statusWire: _remoteRunnerStatusWire,
    );
    _updateState(() => _exportingRemoteRevocation = true);
    Object? localError;
    Object? remoteError;
    try {
      try {
        await _changeDroneEnabled(false, requirePersistence: true);
      } catch (error) {
        localError = error;
      }
      if (remoteMayHoldAuthority) {
        try {
          final profiles =
              await _module.remoteRunnerProvisioning.loadProfiles();
          if (profiles.length != 1) {
            throw StateError('Exactly one Capsule Runner is required.');
          }
          await _revokeRemoteSession(profiles.single);
          await _refreshRemoteRunnerSummary();
        } catch (error) {
          remoteError = error;
        }
      }

      if (localError == null && remoteError == null) {
        await _showSnack(
          remoteMayHoldAuthority
              ? 'Trading authority revoked on this computer and VPS.'
              : 'Trading authority revoked on this computer.',
          seconds: 5,
        );
      } else {
        await _module.uiLog.log(
          'bingx.remote_session.emergency_pause.error',
          'local_error=${localError ?? "-"} '
              'remote_error=${remoteError ?? "-"} effect=false',
        );
        await _showSnack(
          remoteError == null
              ? 'Trading is paused, but local persistence was not confirmed: $localError'
              : 'Trading is paused locally, but the VPS stop was not confirmed: $remoteError',
          seconds: 6,
        );
      }
    } finally {
      if (mounted) _updateState(() => _exportingRemoteRevocation = false);
    }
  }

  Future<BingxFuturesRemoteMandateAdmission?> _loadVerifiedRemoteSession(
    BingxFuturesRemoteRunnerProfile profile,
  ) async {
    final canonicalSession = await _module.remoteRunnerProvisioning
        .loadActiveSession(profile);
    if (canonicalSession == null) return null;
    final session = BingxFuturesRemoteMandateAdmission.parseAndVerify(
      untrustedWireBytes: utf8.encode(canonicalSession),
      verifySignature:
          ({
            required messageHashHex,
            required participantIdHex,
            required signatureHex,
          }) => _module.verifyRootCommitmentSignature(
            commitmentHashHex: messageHashHex,
            capsuleRootHex: participantIdHex,
            signatureHex: signatureHex,
          ),
    );
    if (session == null ||
        !session.isDeterministicSession ||
        session.runnerKeyId != profile.runnerKeyId ||
        session.mandate.capsuleRootHex != profile.capsuleHex ||
        session.mandate.accountBindingHashHex !=
            profile.accountBindingHashHex) {
      throw StateError('The retained VPS session is not authentic.');
    }
    return session;
  }

  Future<void> _refreshRemoteRunnerSummary({
    bool restoreCompletedEffects = true,
  }) async {
    final capsuleRootHex = _module.activeCapsuleRootHex();
    if (capsuleRootHex == null) {
      if (mounted) {
        _updateState(() {
          _loadingRemoteRunnerSummary = false;
          _remoteRunnerConfigured = false;
          _remoteRunnerStatusWire = null;
          _remoteRunnerSession = null;
          _remoteRunnerStatusUnavailable = false;
        });
      }
      return;
    }
    if (mounted) {
      _updateState(() {
        _loadingRemoteRunnerSummary = true;
        _remoteRunnerStatusUnavailable = false;
      });
    }
    try {
      final profiles = await _module.remoteRunnerProvisioning.loadProfiles();
      if (!mounted || _module.activeCapsuleRootHex() != capsuleRootHex) return;
      if (profiles.isEmpty) {
        _updateState(() {
          _loadingRemoteRunnerSummary = false;
          _remoteRunnerConfigured = false;
          _remoteRunnerStatusWire = null;
          _remoteRunnerSession = null;
        });
        return;
      }
      final profile = profiles.single;
      final status = await _module.remoteRunnerProvisioning.status(profile);
      final retainedSession = await _loadVerifiedRemoteSession(profile);
      final session = tradingRemoteRunnerCurrentSession(
        statusWire: status,
        retainedSession: retainedSession,
      );
      if (!mounted || _module.activeCapsuleRootHex() != capsuleRootHex) return;
      _updateState(() {
        _loadingRemoteRunnerSummary = false;
        _remoteRunnerConfigured = true;
        _remoteRunnerStatusWire = status;
        _remoteRunnerSession = session;
      });
      if (retainedSession != null &&
          !tradingRemoteRunnerStatusMatchesSession(
            statusWire: status,
            session: retainedSession,
          )) {
        await _module.uiLog.log(
          'bingx.remote_session.projection_mismatch',
          'local_operation_id=${retainedSession.operationId} effect=false',
        );
      } else if (restoreCompletedEffects && retainedSession != null) {
        await _restoreRemoteCompletedEffects(
          profile: profile,
          session: retainedSession,
        );
      }
      if (tradingRemoteRunnerIsRunning(status) && _localRunnerRunning) {
        await _stopLocalRunner(reason: 'vps_session_running');
        await _showSnack(
          'Trading stopped on this computer because the VPS session is running.',
          seconds: 5,
        );
      }
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_runner.summary.error',
        'error=$error effect=false',
      );
      if (!mounted || _module.activeCapsuleRootHex() != capsuleRootHex) return;
      _updateState(() {
        _loadingRemoteRunnerSummary = false;
        _remoteRunnerStatusWire = null;
        _remoteRunnerSession = null;
        _remoteRunnerStatusUnavailable = true;
      });
    }
  }

  Future<bool> _restoreRemoteCompletedEffects({
    required BingxFuturesRemoteRunnerProfile profile,
    required BingxFuturesRemoteMandateAdmission session,
  }) async {
    try {
      final operations = await _module.remoteRunnerProvisioning
          .completedSessionEffects(
            profile: profile,
            sessionOperationId: session.operationId,
          );
      if (operations.isEmpty) return false;
      final retained = await _module.executionUseCase
          .retainRemoteCompletedEffects(
            session: session,
            operations: operations,
            expectedAccountBindingHashHex: profile.accountBindingHashHex,
          );
      if (!mounted ||
          _module.activeCapsuleRootHex() != session.mandate.capsuleRootHex) {
        return false;
      }
      _updateState(() {
        tradingSynchronizeManagedOrderState(
          state: retained,
          managedOrderIds: _managedOrderIds,
          managedOrderSymbols: _managedOrderSymbols,
          managedOrderProvenance: _managedOrderProvenance,
        );
      });
      await _module.uiLog.log(
        'bingx.remote_session.effects_restored',
        'session_operation_id=${session.operationId} '
            'count=${operations.length} '
            'provenance_count=${retained.managedOrderProvenance.length} '
            'effect=false',
      );
      return true;
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_session.effects_restore.error',
        'error=$error effect=false',
      );
      return false;
    }
  }

  Future<void> _manageRemoteRunners() async {
    if (_exportingRemoteRevocation) return;
    _updateState(() => _exportingRemoteRevocation = true);
    try {
      var profiles = await _module.remoteRunnerProvisioning.loadProfiles();
      if (!mounted) return;
      if (profiles.isEmpty) {
        final credentials = await _loadCredentials();
        if (credentials == null) {
          await _showSnack('Save BingX Futures credentials first.');
          return;
        }
        final profile = await _configureRemoteRunner(
          accountBindingHashHex: _module.accountBindingHashHex(credentials),
        );
        if (profile == null || !mounted) return;
        profiles = [profile];
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder:
            (sheetContext) => SafeArea(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    const ListTile(
                      title: Text(
                        'Remote Runner',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('Capsule-scoped VPS status and controls'),
                    ),
                    ...profiles.map(
                      (profile) => _RemoteRunnerProfileTile(
                        profile: profile,
                        update: () async {
                          final updated = await _configureRemoteRunner(
                            accountBindingHashHex:
                                profile.accountBindingHashHex,
                            currentProfile: profile,
                          );
                          return updated == null
                              ? 'Runner update cancelled'
                              : 'Runner updated';
                        },
                        loadStatus:
                            () => _module.remoteRunnerProvisioning.status(
                              profile,
                            ),
                        pause:
                            () =>
                                _module.remoteRunnerProvisioning.pause(profile),
                        resume: () => _resumeRemoteRunnerSession(profile),
                        revoke: () => _revokeRemoteSession(profile),
                        remove:
                            () => _module.remoteRunnerProvisioning.remove(
                              profile,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      );
      await _refreshRemoteRunnerSummary();
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_runner.manage.error',
        'error=$error effect=false',
      );
      await _showSnack('Remote Runner could not be loaded: $error', seconds: 5);
    } finally {
      if (mounted) _updateState(() => _exportingRemoteRevocation = false);
    }
  }

  Future<String> _resumeRemoteRunnerSession(
    BingxFuturesRemoteRunnerProfile profile,
  ) async {
    if (_startingLocalRunner || _localRunnerRunning) {
      throw StateError(
        'Stop trading on this computer before resuming the VPS session.',
      );
    }
    final status = await _module.remoteRunnerProvisioning.status(profile);
    if (!tradingRemoteRunnerCanResume(status)) {
      throw StateError('The retained session is not paused and resumable.');
    }
    final sessionOperationId = tradingRemoteRunnerSessionOperationId(status);
    if (sessionOperationId == null) {
      throw StateError('The VPS did not identify its resumable session.');
    }
    final result = await _module.remoteRunnerProvisioning.resume(profile);
    await _module.uiLog.log(
      'bingx.remote_session.resumed',
      'session_operation_id=$sessionOperationId '
          'runner_key_id=${profile.runnerKeyId} effect=false',
    );
    if (mounted) {
      await _showSnack('Same signed VPS session resumed.', seconds: 4);
    }
    return result;
  }

  Future<void> _resumeConfiguredRemoteRunnerSession() async {
    if (_exportingRemoteMandate) return;
    if (_startingLocalRunner || _localRunnerRunning) {
      await _showSnack(
        'Stop trading on this computer before resuming the VPS session.',
        seconds: 5,
      );
      return;
    }
    _updateState(() => _exportingRemoteMandate = true);
    try {
      final profiles = await _module.remoteRunnerProvisioning.loadProfiles();
      if (profiles.length != 1) {
        throw StateError('Exactly one Capsule Runner is required.');
      }
      await _resumeRemoteRunnerSession(profiles.single);
      await _refreshRemoteRunnerSummary();
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_session.resume.error',
        'error=$error effect=false',
      );
      await _showSnack('VPS session could not resume: $error', seconds: 5);
    } finally {
      if (mounted) _updateState(() => _exportingRemoteMandate = false);
    }
  }

  Future<void> _exportSignedRemoteDeterministicSession() async {
    if (_exportingRemoteMandate) return;
    _updateState(() => _exportingRemoteMandate = true);
    try {
      await _exportSignedRemoteDeterministicSessionOnce();
    } finally {
      if (mounted) _updateState(() => _exportingRemoteMandate = false);
    }
  }

  Future<void> _exportSignedRemoteDeterministicSessionOnce() async {
    if (_startingLocalRunner || _localRunnerRunning) {
      await _showSnack(
        'Stop trading on this computer before authorizing the VPS session.',
        seconds: 5,
      );
      return;
    }
    var mandate = _tradingMandate;
    if (!_droneEnabled ||
        mandate == null ||
        !mandate.isActiveAt(DateTime.now().toUtc())) {
      if (!await _changeDroneEnabled(true)) return;
      mandate = _tradingMandate;
    }
    if (mandate == null || !mandate.isActiveAt(DateTime.now().toUtc())) {
      await _showSnack('Bounded trading authority could not be activated.');
      return;
    }
    final activeMandate = mandate;
    final selectionNotice = tradingMandateSelectionNotice(
      mandate: activeMandate,
      droneEnabled: _droneEnabled,
      selectedSymbol: _symbolController.text,
      selectedMaxNotional: _maxNotionalUsdtController.text,
      selectedMaxEffects: _maxEffects,
      testOrder: _useTestOrderEndpoint,
      nowUtc: DateTime.now().toUtc(),
    );
    if (selectionNotice != null) {
      await _showSnack(selectionNotice, seconds: 5);
      return;
    }
    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _showSnack('Save BingX Futures credentials first.');
      return;
    }
    final leverage = await _module.exchangeService.getLeverage(
      credentials: credentials,
      symbol: activeMandate.symbol,
    );
    final nominalStopLossLimitPercent = _module.riskGovernor
        .nominalStopLossLimitPercent(
          longLeverage: leverage.longLeverage,
          shortLeverage: leverage.shortLeverage,
        );
    final leverageNotice = tradingRemoteSessionStopLossNotice(
      stopLossPercent: _stopLossPercent,
      leverageVerified: leverage.isSuccess,
      longLeverage: leverage.longLeverage,
      shortLeverage: leverage.shortLeverage,
      nominalStopLossLimitPercent: nominalStopLossLimitPercent,
    );
    if (leverageNotice != null) {
      await _module.uiLog.log(
        'bingx.remote_session.leverage_blocked',
        'symbol=${activeMandate.symbol} '
            'sl_pct=${_stopLossPercent.toStringAsFixed(2)} '
            'long_leverage=${leverage.longLeverage ?? "-"} '
            'short_leverage=${leverage.shortLeverage ?? "-"} effect=false',
      );
      await _showSnack(leverageNotice, seconds: 6);
      return;
    }
    final accountBindingHashHex = _module.accountBindingHashHex(credentials);
    final runner = await _selectRemoteRunner(
      activeMandate,
      accountBindingHashHex: accountBindingHashHex,
    );
    if (runner == null) return;
    if (!mounted) return;
    const intervalSeconds = tradingRemoteSessionIntervalSeconds;
    final startsAtUtc = tradingRemoteSessionFirstCycleStart(
      DateTime.now().toUtc(),
    );
    final firstCycleDeadlineUtc = startsAtUtc.add(
      const Duration(seconds: intervalSeconds),
    );
    final expiresAtUtc = DateTime.tryParse(activeMandate.expiresAtUtc)?.toUtc();
    if (expiresAtUtc == null) {
      await _showSnack('The active mandate has an invalid expiry.');
      return;
    }
    final remainingSeconds = expiresAtUtc.difference(startsAtUtc).inSeconds;
    final maxCycles = ((remainingSeconds - 1) ~/ intervalSeconds + 1).clamp(
      1,
      BingxFuturesRemoteMandateAdmission.maxSessionCycles,
    );
    var selectedStrategyVersion = bingxLiquidityStrategyVersion;
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Authorize VPS trading session?'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedStrategyVersion,
                          decoration: const InputDecoration(
                            labelText: 'Entry strategy',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: bingxLiquidityStrategyVersion,
                              child: Text('4h zones / 15m checks'),
                            ),
                            DropdownMenuItem(
                              value: bingxHourlyLiquidityStrategyVersion,
                              child: Text('1h zones / 5m checks'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(
                                () => selectedStrategyVersion = value,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Symbol: ${activeMandate.symbol}\n'
                          'Mode: ${activeMandate.testOrder ? "test" : "live"}\n'
                          'Check interval: 5 minutes\n'
                          'First check: ${startsAtUtc.toIso8601String()}\n'
                          'Activate before: ${firstCycleDeadlineUtc.toIso8601String()}\n'
                          'Maximum checks: $maxCycles\n'
                          'Maximum entry attempts: ${activeMandate.maxEffects}\n'
                          'After that limit: continue checks and permitted cancellation '
                          'of this session\'s pending orders, without new entries.\n'
                          'Exchange leverage: long ${leverage.longLeverage}x, '
                          'short ${leverage.shortLeverage}x\n'
                          'Loss budget: ${_stopLossPercent.toStringAsFixed(1)}% of maximum notional\n'
                          'Stop: entry structure / ATR; wider stops reduce order size.\n'
                          'Authorized reads: balance, positions, realized PnL, and '
                          '${activeMandate.symbol} leverage and margin mode.\n'
                          'Expires: ${activeMandate.expiresAtUtc}\n\n'
                          'The VPS may evaluate only this signed strategy and mandate. '
                          'Every exchange attempt remains bounded by the existing effect journal.',
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Authorize session'),
                    ),
                  ],
                ),
          ),
    );
    if (approved != true) return;
    if (!DateTime.now().toUtc().isBefore(startsAtUtc)) {
      await _showSnack(
        'The VPS provisioning window elapsed. Review a fresh session.',
        seconds: 5,
      );
      return;
    }
    final admission =
        BingxFuturesRemoteMandateAdmission.issueDeterministicSession(
          mandate: activeMandate,
          runnerKeyId: runner.runnerKeyId,
          strategyPolicy:
              BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
                stopLossPercent: _stopLossPercent,
                minimumRiskReward: _takeProfitRiskReward,
                includeOpenOrders: true,
                strategyVersion: selectedStrategyVersion,
              ),
          startsAtUtc: startsAtUtc,
          intervalSeconds: intervalSeconds,
          maxCycles: maxCycles,
          manageExistingAfterEntryBudget: true,
          signCommitment: _module.signRootCommitment,
        );
    if (admission == null ||
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
              untrustedWireBytes: utf8.encode(admission.canonicalJson),
              verifySignature:
                  ({
                    required messageHashHex,
                    required participantIdHex,
                    required signatureHex,
                  }) => _module.verifyRootCommitmentSignature(
                    commitmentHashHex: messageHashHex,
                    capsuleRootHex: participantIdHex,
                    signatureHex: signatureHex,
                  ),
            ) ==
            null) {
      await _showSnack('Capsule could not sign the remote session.');
      return;
    }
    try {
      await _module.remoteRunnerProvisioning.deploySession(
        profile: runner,
        accountBindingHashHex: accountBindingHashHex,
        canonicalSessionJson: admission.canonicalJson,
        apiKey: credentials.apiKey,
        apiSecret: credentials.apiSecret,
      );
      await _module.uiLog.log(
        'bingx.remote_session.deployed',
        'operation_id=${admission.operationId} '
            'runner_key_id=${admission.runnerKeyId} '
            'starts_at_utc=${startsAtUtc.toIso8601String()} '
            'first_cycle_deadline_utc=${firstCycleDeadlineUtc.toIso8601String()} '
            'max_cycles=$maxCycles interval_seconds=$intervalSeconds effect=false',
      );
      await _showSnack('Remote Runner is enabled.', seconds: 5);
      await _refreshRemoteRunnerSummary();
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_session.deploy.error',
        'operation_id=${admission.operationId} error=$error effect=false',
      );
      await _showSnack('Remote Runner activation failed: $error', seconds: 5);
    }
  }

  Future<String> _revokeRemoteSession(
    BingxFuturesRemoteRunnerProfile profile,
  ) async {
    final status = await _module.remoteRunnerProvisioning.status(profile);
    if (!tradingRemoteRunnerCanRevoke(status)) {
      return 'The VPS has no active trading authority to revoke.';
    }
    final sessionOperationId = tradingRemoteRunnerSessionOperationId(status);
    if (sessionOperationId == null) {
      throw StateError('The VPS did not identify its active session.');
    }
    final revocation = BingxFuturesRemoteSessionRevocation.issue(
      targetSessionOperationId: sessionOperationId,
      runnerKeyId: profile.runnerKeyId,
      capsuleRootHex: profile.capsuleHex,
      revokedAtUtc: DateTime.now().toUtc(),
      signCommitment: _module.signRootCommitment,
    );
    if (revocation == null) {
      throw StateError('Capsule could not sign the VPS session revocation.');
    }
    final result = await _module.remoteRunnerProvisioning.revokeSession(
      profile: profile,
      canonicalRevocationJson: revocation.canonicalJson,
    );
    if (_droneEnabled) {
      await _changeDroneEnabled(false, requirePersistence: true);
    }
    await _module.uiLog.log(
      'bingx.remote_session.revoked',
      'session_operation_id=$sessionOperationId '
          'revocation_id=${revocation.revocationId} '
          'runner_key_id=${profile.runnerKeyId} effect=false',
    );
    return result;
  }

  Future<BingxFuturesRemoteRunnerProfile?> _selectRemoteRunner(
    BingxFuturesTradingMandate mandate, {
    required String accountBindingHashHex,
  }) async {
    final expectedCapsuleRootHex = _module.activeCapsuleRootHex();
    if (expectedCapsuleRootHex == null) {
      await _showSnack('Active Capsule is unavailable.');
      return null;
    }
    String? errorText;
    var provisioning = false;
    var profiles = await _module.remoteRunnerProvisioning.loadProfiles();
    BingxFuturesRemoteRunnerProfile? selectedProfile;
    for (final profile in profiles) {
      if (profile.accountBindingHashHex == accountBindingHashHex) {
        selectedProfile = profile;
        break;
      }
    }
    if (!mounted) return null;
    final result = await showDialog<BingxFuturesRemoteRunnerProfile>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Select trusted VPS runner'),
                  content: SizedBox(
                    width: 560,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${mandate.symbol} · '
                          '${mandate.testOrder ? "TEST" : "LIVE"}\n'
                          'Max order: '
                          '${mandate.maxOrderNotionalQuoteDecimal} USDT · '
                          'Loss budget: ${_stopLossPercent.toStringAsFixed(1)}% of maximum notional · '
                          'Minimum RR: '
                          '${_takeProfitRiskReward.toStringAsFixed(1)}',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The Capsule signs authority for this bounded session. '
                          'The runner cannot extend or renew its limits.',
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed:
                                  provisioning
                                      ? null
                                      : () async {
                                        setDialogState(() {
                                          provisioning = true;
                                          errorText = null;
                                        });
                                        await _module.uiLog.log(
                                          'bingx.remote_runner.provision.start',
                                          'mode=${profiles.isEmpty ? "add" : "update"} effect=false',
                                        );
                                        try {
                                          final profile =
                                              await _configureRemoteRunner(
                                                accountBindingHashHex:
                                                    profiles.isEmpty
                                                        ? accountBindingHashHex
                                                        : profiles
                                                            .single
                                                            .accountBindingHashHex,
                                                currentProfile:
                                                    profiles.isEmpty
                                                        ? null
                                                        : profiles.single,
                                              );
                                          if (profile != null) {
                                            profiles =
                                                await _module
                                                    .remoteRunnerProvisioning
                                                    .loadProfiles();
                                            selectedProfile = profile;
                                            await _module.uiLog.log(
                                              'bingx.remote_runner.provision.success',
                                              'profile_id=${profile.profileId} effect=false',
                                            );
                                          }
                                        } on FormatException catch (error) {
                                          errorText = error.message;
                                          await _module.uiLog.log(
                                            'bingx.remote_runner.provision.error',
                                            'error=$error effect=false',
                                          );
                                        } catch (error) {
                                          errorText = '$error';
                                          await _module.uiLog.log(
                                            'bingx.remote_runner.provision.error',
                                            'error=$error effect=false',
                                          );
                                        } finally {
                                          if (context.mounted) {
                                            setDialogState(() {
                                              provisioning = false;
                                            });
                                          }
                                        }
                                      },
                              icon:
                                  provisioning
                                      ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.dns_rounded),
                              label: Text(
                                profiles.isEmpty ? 'Add VPS' : 'Update VPS',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (profiles.isEmpty)
                          const Text('No Remote Runner is configured.')
                        else
                          ...profiles.map((profile) {
                            final accountCompatible =
                                profile.accountBindingHashHex ==
                                accountBindingHashHex;
                            final runnerCompatible =
                                profile.runnerBuildId ==
                                BingxFuturesRemoteMandateAdmission
                                    .deterministicRunnerBuildId;
                            final compatible =
                                tradingRemoteRunnerProfileIsCompatible(
                                  profile: profile,
                                  accountBindingHashHex: accountBindingHashHex,
                                );
                            return ListTile(
                              enabled: compatible,
                              selected:
                                  selectedProfile?.profileId ==
                                  profile.profileId,
                              leading: Icon(
                                compatible
                                    ? Icons.cloud_done_rounded
                                    : Icons.lock_outline_rounded,
                              ),
                              title: Text('${profile.host}:${profile.port}'),
                              subtitle: Text(
                                !accountCompatible
                                    ? 'Bound to another BingX account'
                                    : !runnerCompatible
                                    ? 'Update required · installed ${profile.runnerBuildId}'
                                    : 'Ready · ${profile.runnerBuildId}',
                              ),
                              onTap:
                                  compatible
                                      ? () => setDialogState(
                                        () => selectedProfile = profile,
                                      )
                                      : null,
                            );
                          }),
                        if (errorText != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          provisioning
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          provisioning
                              ? null
                              : () {
                                final profile = selectedProfile;
                                if (profile == null) {
                                  setDialogState(() {
                                    errorText =
                                        'Add or select a Runner for this account.';
                                  });
                                  return;
                                }
                                Navigator.of(dialogContext).pop(profile);
                              },
                      icon: const Icon(Icons.draw_rounded),
                      label: const Text('Review and sign'),
                    ),
                  ],
                ),
          ),
    );
    return result;
  }

  Future<BingxFuturesRemoteRunnerProfile?> _configureRemoteRunner({
    required String accountBindingHashHex,
    BingxFuturesRemoteRunnerProfile? currentProfile,
  }) async {
    if (_provisioningRemoteRunner) {
      await _showSnack('Remote Runner setup is already in progress.');
      return null;
    }
    _updateState(() => _provisioningRemoteRunner = true);
    final host = TextEditingController(text: currentProfile?.host ?? '');
    final port = TextEditingController(text: '${currentProfile?.port ?? 22}');
    final username = TextEditingController(text: 'root');
    final password = TextEditingController();
    String? validationErrorText;
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => StatefulBuilder(
              builder:
                  (context, setDialogState) => AlertDialog(
                    title: Text(
                      currentProfile == null
                          ? 'Add Remote Runner VPS'
                          : 'Update Remote Runner VPS',
                    ),
                    content: SizedBox(
                      width: 480,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: host,
                            readOnly: currentProfile != null,
                            decoration: const InputDecoration(
                              labelText: 'Host or IP',
                              hintText: '45.142.176.16',
                            ),
                          ),
                          TextField(
                            controller: port,
                            readOnly: currentProfile != null,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'SSH port',
                            ),
                          ),
                          TextField(
                            controller: username,
                            decoration: const InputDecoration(
                              labelText: 'Admin user',
                            ),
                          ),
                          TextField(
                            controller: password,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'One-time admin password',
                              helperText:
                                  'Used once. Hivra never stores this password.',
                            ),
                          ),
                          if (validationErrorText != null) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                validationErrorText!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final normalizedHost = host.text.trim();
                          final parsedPort = int.tryParse(port.text.trim());
                          String? validationError;
                          if (normalizedHost.isEmpty) {
                            validationError = 'Enter the VPS host or IP.';
                          } else if (normalizedHost.contains(
                            RegExp(r'[\s/\\@]'),
                          )) {
                            validationError =
                                'Host must contain only a hostname or IP, without ssh:// or user@.';
                          } else if (parsedPort == null ||
                              parsedPort < 1 ||
                              parsedPort > 65535) {
                            validationError = 'Enter a valid SSH port.';
                          } else if (username.text.trim() != 'root') {
                            validationError =
                                'The current bootstrap requires the root admin user.';
                          } else if (password.text.isEmpty) {
                            validationError =
                                'Enter the one-time admin password.';
                          }
                          if (validationError != null) {
                            setDialogState(() {
                              validationErrorText = validationError;
                            });
                            return;
                          }
                          Navigator.of(dialogContext).pop(true);
                        },
                        child: const Text('Connect securely'),
                      ),
                    ],
                  ),
            ),
      );
      if (submitted != true) return null;
      final parsedPort = int.tryParse(port.text.trim());
      if (parsedPort == null) {
        throw const FormatException('SSH port is invalid.');
      }
      return await _module.remoteRunnerProvisioning.bootstrap(
        host: host.text,
        port: parsedPort,
        rootUsername: username.text,
        rootPassword: password.text,
        accountBindingHashHex: accountBindingHashHex,
        confirmHostKey: (algorithm, fingerprint) async {
          if (!mounted) return false;
          return await showDialog<bool>(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('Trust this VPS?'),
                      content: SelectableText(
                        'Host: ${host.text.trim()}:$parsedPort\n'
                        'Key type: $algorithm\n'
                        'Fingerprint: $fingerprint\n\n'
                        'Confirm this fingerprint before Hivra sends the one-time password.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Trust and continue'),
                        ),
                      ],
                    ),
              ) ??
              false;
        },
      );
    } finally {
      if (mounted) _updateState(() => _provisioningRemoteRunner = false);
      password.clear();
      host.dispose();
      port.dispose();
      username.dispose();
      password.dispose();
    }
  }
}

Map<String, String>? _tradingRemoteRunnerStatusFields(String raw) {
  if (raw.trim().isEmpty || raw.length > 4096) return null;
  final fields = <String, String>{};
  for (final token in raw.trim().split(RegExp(r'\s+'))) {
    final separator = token.indexOf('=');
    if (separator <= 0) return null;
    final key = token.substring(0, separator);
    if (fields.containsKey(key)) return null;
    fields[key] = token.substring(separator + 1);
  }
  if (!{'active', 'inactive', 'failed'}.contains(fields['active'])) return null;
  final state = fields['session_state'];
  if (state == null || {'absent', 'unavailable'}.contains(state)) {
    if (fields.containsKey('session_operation_id')) return null;
    return fields;
  }
  if (!{'active', 'completed', 'stopped', 'expired'}.contains(state)) {
    return null;
  }
  final sessionOperationId = fields['session_operation_id'];
  if (sessionOperationId == null ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(sessionOperationId)) {
    return null;
  }
  final cycles = int.tryParse(fields['cycles'] ?? '');
  final effects = int.tryParse(fields['effects'] ?? '');
  if (cycles == null ||
      effects == null ||
      cycles < 0 ||
      cycles > 288 ||
      effects < 0 ||
      effects > cycles) {
    return null;
  }
  final outcome = fields['last_outcome'];
  final validOutcome =
      outcome == 'none' && cycles == 0 ||
      cycles > 0 &&
          outcome != null &&
          RegExp(r'^blocked:[a-z0-9_]{1,96}$').hasMatch(outcome) ||
      cycles > 0 &&
          effects > 0 &&
          outcome != null &&
          RegExp(
            r'^effect:(succeeded|unresolved|terminal_failure):test=(true|false)$',
          ).hasMatch(outcome);
  if (!validOutcome) {
    return null;
  }
  final operatorHold = fields['operator_hold'] ?? 'none';
  if (!{
        'none',
        'external_order_active',
        'order_ownership_unavailable',
      }.contains(operatorHold) ||
      operatorHold != 'none' &&
          (fields['active'] != 'inactive' ||
              state != 'active' ||
              outcome != 'blocked:$operatorHold')) {
    return null;
  }
  final last = fields['last_scheduled_check'];
  final next = fields['next_check'];
  bool validTime(String? value) =>
      value != null &&
      RegExp(r'^\d{4}-\d{2}-\d{2}T.*(?:Z|\+00:00)$').hasMatch(value) &&
      DateTime.tryParse(value) != null;
  if ((cycles == 0 ? last != 'none' : !validTime(last)) ||
      (state == 'active' && operatorHold == 'none'
          ? !validTime(next)
          : next != 'none')) {
    return null;
  }
  return fields;
}

String tradingRemoteRunnerStatusLabel(String raw, {int? authorizedMaxEffects}) {
  const unknown = 'Runner status unknown. Refresh to retry.';
  final fields = _tradingRemoteRunnerStatusFields(raw);
  if (fields == null) return unknown;
  final state = fields['session_state'];
  final terminal = {'completed', 'stopped', 'expired'}.contains(state);
  final process = switch ((fields['active'], terminal)) {
    ('active', false) => 'Runner running',
    ('inactive', false) => 'Runner paused',
    ('active', true) || ('inactive', true) => 'Runner stopped',
    ('failed', _) => 'Runner failed',
    _ => throw StateError('Validated Runner process is missing.'),
  };
  final operatorHold = fields['operator_hold'] ?? 'none';
  final startup =
      operatorHold != 'none'
          ? 'Startup blocked until you explicitly resume this signed session.'
          : switch ((fields['enabled'], terminal)) {
            ('enabled', true) =>
              'Autostart remains enabled, but this finished session cannot trade. '
                  'Authorize a new signed session.',
            ('enabled', false) =>
              'WARNING: autostart enabled — a VPS reboot may start the Runner.',
            ('enabled-runtime', true) =>
              'Runtime startup remains enabled, but this finished session cannot trade. '
                  'Authorize a new signed session.',
            ('enabled-runtime', false) =>
              'WARNING: runtime startup activation is enabled.',
            ('linked' || 'linked-runtime' || 'disabled', _) =>
              'Autostart: not enabled.',
            ('masked' || 'masked-runtime', _) =>
              'Startup blocked: service masked.',
            _ =>
              'Autostart status unknown — pause persistence is not verified.',
          };
  if (state == null || state == 'unavailable') {
    return '$process\n$startup\nSession details unavailable on this Runner.';
  }
  if (state == 'absent') {
    return '$process\n$startup\nNo signed trading session is installed on this Runner.';
  }
  final cycles = int.parse(fields['cycles']!);
  final effects = int.parse(fields['effects']!);
  final validEffectLimit =
      authorizedMaxEffects != null &&
      authorizedMaxEffects > 0 &&
      authorizedMaxEffects <= 256 &&
      effects <= authorizedMaxEffects;
  final remainingEffects =
      validEffectLimit ? authorizedMaxEffects - effects : null;
  final outcome = fields['last_outcome']!;
  final authorization =
      state == 'active' && fields['active'] == 'failed'
          ? 'Authorization remains active'
          : 'Session $state';
  final result = switch (outcome) {
    'none' => 'No completed check yet',
    'blocked:managed_order_active' =>
      'No new order: this Runner already has a pending order for the VPS '
          'market. It will not create a duplicate.',
    'blocked:managed_order_revalidation_unavailable' =>
      'Pending order retained: this check could not confirm its zone. '
          'A blocked new entry does not authorize cancellation. '
          'Review the pending order on the exchange.',
    'blocked:external_order_active' =>
      fields['active'] == 'inactive'
          ? 'Runner paused: the exchange has an order for this VPS market '
              'that is not owned by this session. Review the order, then '
              'resume this signed session.'
          : 'No new order: the exchange already has an order for this VPS '
              'market that is not owned by this session. Review it before '
              'the Runner can trade this market.',
    'blocked:order_ownership_unavailable' =>
      fields['active'] == 'inactive'
          ? 'Runner paused because ownership of the existing market order '
              'could not be verified. Review the order before resuming.'
          : 'No new order: ownership of the existing market order could not '
              'be verified.',
    'blocked:active_order_exists' =>
      'No new order: this VPS market already has an open order. '
          'The Runner is waiting to avoid a duplicate.',
    _ when outcome.startsWith('blocked:') =>
      'No order: ${outcome.substring(8).replaceAll('_', ' ')}',
    _ when outcome.contains('succeeded') =>
      outcome.endsWith('true')
          ? 'Test request confirmed — not a live order'
          : 'Provider receipt confirmed',
    _ when outcome.contains('unresolved') =>
      'Outcome unresolved — reconciliation required',
    _ => 'Provider execution failed',
  };
  final last = fields['last_scheduled_check'];
  final next = fields['next_check'];
  return [
    '$process · $authorization',
    startup,
    if (remainingEffects == null)
      'Checks: $cycles · Exchange attempts: $effects'
    else
      'Checks: $cycles · Exchange requests used: $effects of '
          '$authorizedMaxEffects · '
          'Remaining: $remainingEffects',
    'Last retained result: $result',
    if (terminal && remainingEffects == 0)
      'Session ended with no entry attempts remaining. '
          'Check any open order before authorizing a new session; new authority '
          'does not automatically adopt an earlier session\'s order.',
    if (!terminal && remainingEffects == 0)
      'Entry budget exhausted: no new orders. Only checks and authorized '
          'pending-order maintenance remain within this session.',
    if (terminal && outcome == 'effect:succeeded:test=false')
      'The provider receipt does not prove the order is still open. '
          'Check Open Orders to read its current status; this stopped '
          'Runner cannot manage it. A filled order may leave an open position.',
    if (cycles > 0) 'Last completed check slot: $last',
    if (state == 'active' && fields['active'] == 'active')
      'Next scheduled check: $next (not guaranteed execution)',
    if (state == 'active' && fields['active'] == 'failed')
      'The Runner is stopped. No checks or orders can occur until it is updated or resumed.',
    if (state == 'active' && fields['active'] == 'inactive')
      'No checks run while the Runner is paused.',
  ].join('\n');
}

@visibleForTesting
bool tradingRemoteRunnerCanResume(String raw) {
  final fields = _tradingRemoteRunnerStatusFields(raw);
  return fields != null &&
      fields['active'] == 'inactive' &&
      fields['session_state'] == 'active' &&
      {
        'enabled',
        'linked',
        'linked-runtime',
        'disabled',
      }.contains(fields['enabled']);
}

@visibleForTesting
bool tradingRemoteRunnerIsRunning(String raw) {
  final fields = _tradingRemoteRunnerStatusFields(raw);
  return fields != null &&
      fields['active'] == 'active' &&
      fields['session_state'] == 'active';
}

@visibleForTesting
bool tradingRemoteRunnerCanPause(String raw) {
  final fields = _tradingRemoteRunnerStatusFields(raw);
  return fields != null &&
      {'active', 'failed'}.contains(fields['active']) &&
      fields['session_state'] == 'active';
}

@visibleForTesting
bool tradingRemoteRunnerCanRevoke(String raw) {
  final fields = _tradingRemoteRunnerStatusFields(raw);
  return fields != null && fields['session_state'] == 'active';
}

@visibleForTesting
bool tradingRemoteRunnerCanStartSession({required String raw}) {
  final fields = _tradingRemoteRunnerStatusFields(raw);
  if (fields == null ||
      fields['active'] != 'inactive' ||
      !{
        'enabled',
        'enabled-runtime',
        'linked',
        'linked-runtime',
        'disabled',
      }.contains(fields['enabled'])) {
    return false;
  }
  final state = fields['session_state'];
  return {'absent', 'completed', 'stopped', 'expired'}.contains(state);
}

@visibleForTesting
String tradingRemoteRunnerSessionDetailsLabel(
  BingxFuturesRemoteMandateAdmission? session,
) {
  if (session == null || !session.isDeterministicSession) {
    return 'No verified signed session is retained.';
  }
  String short(String value) => value.substring(0, 8);
  String number(Object? value) {
    final parsed = value is num ? value.toDouble() : double.nan;
    if (!parsed.isFinite) return 'unknown';
    return parsed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  final strategy = session.strategyPolicy!;
  final policy = session.sessionPolicy!;
  final intervalSeconds = policy['interval_seconds'] as int;
  final entryStrategy =
      strategy['strategy_version'] == bingxHourlyLiquidityStrategyVersion
          ? '1h zones / 5m checks'
          : '4h zones / 15m checks';
  return <String>[
    '${session.mandate.symbol} · ${session.mandate.testOrder ? "TEST" : "LIVE"}',
    'Entry strategy: $entryStrategy',
    'Limit ${session.mandate.maxOrderNotionalQuoteDecimal} USDT · '
        'Up to ${session.mandate.maxEffects} exchange request${session.mandate.maxEffects == 1 ? "" : "s"}',
    '${strategy['strategy_version'] == null ? 'SL' : 'Loss budget'} ${number(strategy['stop_loss_percent'])}% · '
        'Minimum R:R ${number(strategy['minimum_risk_reward'])}',
    'Checks every ${intervalSeconds ~/ 60} min · '
        'Up to ${policy['max_cycles']} checks',
    'Expires ${session.mandate.expiresAtUtc}',
    'Session ${short(session.operationId)} · '
        'Capsule ${short(session.mandate.capsuleRootHex)} · '
        'Account ${short(session.mandate.accountBindingHashHex)}',
  ].join('\n');
}

@visibleForTesting
String tradingRemoteRunnerSummaryLabel({
  required bool loading,
  required bool configured,
  required bool unavailable,
  required String? statusWire,
  int? authorizedMaxEffects,
}) {
  if (loading) return 'Checking the 24/7 Runner…';
  if (!configured && !unavailable) {
    return 'No VPS Runner is installed for this Capsule.';
  }
  if (unavailable) {
    return 'Runner status unavailable. Refresh to retry.';
  }
  if (statusWire == null || statusWire.trim().isEmpty) {
    return 'Runner configured. Refresh to unlock and check status.';
  }
  return tradingRemoteRunnerStatusLabel(
    statusWire,
    authorizedMaxEffects: authorizedMaxEffects,
  );
}

@visibleForTesting
String tradingRemoteRunnerPrimaryActionLabel({
  required bool configured,
  required bool running,
  required bool resumable,
}) {
  if (!configured) return 'Set up VPS Runner';
  if (resumable) return 'Resume VPS session';
  if (running) return 'VPS session running';
  return 'Authorize VPS session';
}

@visibleForTesting
bool tradingRemoteRunnerPrimaryActionEnabled({
  required bool configured,
  required bool running,
  required bool resumable,
  required bool canStart,
  required bool localActive,
}) {
  if (localActive) return false;
  if (!configured) return true;
  if (running) return false;
  if (resumable) return true;
  return canStart;
}

@visibleForTesting
String tradingRemoteRunnerControlNotice({
  required bool configured,
  required bool running,
  required bool resumable,
}) {
  if (!configured) {
    return 'Set up the VPS first. You do not need to pause trading in this app.';
  }
  if (running) {
    return 'The VPS session runs independently. Pausing this app does not stop it.';
  }
  if (resumable) {
    return 'Resume the same signed VPS session; no new authority is created.';
  }
  return 'Authorize one bounded VPS session. The app shows when renewal is required.';
}

class _RemoteRunnerProfileTile extends StatefulWidget {
  final BingxFuturesRemoteRunnerProfile profile;
  final Future<String> Function() update;
  final Future<String> Function() loadStatus;
  final Future<String> Function() pause;
  final Future<String> Function() resume;
  final Future<String> Function() revoke;
  final Future<String> Function() remove;

  const _RemoteRunnerProfileTile({
    required this.profile,
    required this.update,
    required this.loadStatus,
    required this.pause,
    required this.resume,
    required this.revoke,
    required this.remove,
  });

  @override
  State<_RemoteRunnerProfileTile> createState() =>
      _RemoteRunnerProfileTileState();
}

class _RemoteRunnerProfileTileState extends State<_RemoteRunnerProfileTile> {
  late Future<String> _status = _loadStatus();
  String? _statusWire;
  var _pausing = false;
  var _removed = false;
  String? _actionError;

  Future<String> _loadStatus() async {
    final status = await widget.loadStatus();
    if (mounted) {
      setState(() => _statusWire = status);
    } else {
      _statusWire = status;
    }
    return status;
  }

  Future<void> _runAction(
    Future<String> Function() action, {
    bool marksRemoved = false,
  }) async {
    setState(() {
      _pausing = true;
      _actionError = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _removed = marksRemoved;
        _status =
            marksRemoved
                ? Future<String>.value('VPS Runner uninstalled')
                : _loadStatus();
      });
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.profile.host}:${widget.profile.port}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            FutureBuilder<String>(
              future: _status,
              builder: (context, snapshot) {
                final label =
                    snapshot.connectionState == ConnectionState.waiting
                        ? 'Checking status…'
                        : snapshot.hasError
                        ? 'Runner status unavailable. Refresh to retry.'
                        : _removed
                        ? 'VPS Runner uninstalled'
                        : tradingRemoteRunnerStatusLabel(snapshot.data ?? '');
                return Text(label);
              },
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 8),
              Text(
                _actionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      _pausing || _removed
                          ? null
                          : () => _runAction(widget.update),
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: const Text('Update Runner'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _pausing
                          ? null
                          : () => setState(() => _status = _loadStatus()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
                if (tradingRemoteRunnerCanPause(_statusWire ?? ''))
                  FilledButton.tonalIcon(
                    onPressed: _pausing ? null : () => _runAction(widget.pause),
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: Text(_pausing ? 'Pausing' : 'Pause VPS session'),
                  ),
                if (tradingRemoteRunnerCanResume(_statusWire ?? ''))
                  FilledButton.tonalIcon(
                    onPressed:
                        _pausing ? null : () => _runAction(widget.resume),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: Text(_pausing ? 'Resuming' : 'Resume VPS session'),
                  ),
                if (tradingRemoteRunnerCanRevoke(_statusWire ?? ''))
                  OutlinedButton.icon(
                    onPressed:
                        _pausing || _removed
                            ? null
                            : () async {
                              final confirmed =
                                  await showDialog<bool>(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: const Text(
                                            'Revoke trading authority?',
                                          ),
                                          content: const Text(
                                            'The Capsule signs an exact revocation. '
                                            'The VPS stops that session and cannot '
                                            'resume it. A new session must be authorized.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.of(
                                                    context,
                                                  ).pop(false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed:
                                                  () => Navigator.of(
                                                    context,
                                                  ).pop(true),
                                              child: const Text(
                                                'Revoke authority',
                                              ),
                                            ),
                                          ],
                                        ),
                                  ) ??
                                  false;
                              if (!confirmed || !mounted) return;
                              await _runAction(widget.revoke);
                            },
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Revoke trading authority'),
                  ),
                OutlinedButton.icon(
                  onPressed:
                      _pausing || _removed
                          ? null
                          : () async {
                            final confirmed =
                                await showDialog<bool>(
                                  context: context,
                                  builder:
                                      (context) => AlertDialog(
                                        title: const Text(
                                          'Uninstall Runner from VPS?',
                                        ),
                                        content: Text(
                                          'This stops and removes only the Hivra Trading Runner from '
                                          '${widget.profile.host}:${widget.profile.port}, '
                                          'then deletes this Capsule\'s local control binding. '
                                          'It does not pause trading in this app and it is not a restart. '
                                          'Using this VPS again requires setup.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.of(
                                                  context,
                                                ).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed:
                                                () => Navigator.of(
                                                  context,
                                                ).pop(true),
                                            child: const Text(
                                              'Uninstall from VPS',
                                            ),
                                          ),
                                        ],
                                      ),
                                ) ??
                                false;
                            if (!confirmed || !mounted) return;
                            await _runAction(widget.remove, marksRemoved: true);
                          },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(
                    _removed ? 'Uninstalled' : 'Uninstall Runner from VPS',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
