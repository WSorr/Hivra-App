part of 'trading_drone_screen.dart';

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
  Future<bool> _restoreRemoteCompletedEffects() async {
    try {
      final profiles = await _module.remoteRunnerProvisioning.loadProfiles();
      if (profiles.length != 1) return false;
      final profile = profiles.single;
      final canonicalSession = await _module.remoteRunnerProvisioning
          .loadActiveSession(profile);
      if (canonicalSession == null) return false;
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
      final operations = await _module.remoteRunnerProvisioning
          .completedSessionEffects(
            profile: profile,
            sessionOperationId: session.operationId,
          );
      if (operations.isEmpty) return false;
      await _module.executionUseCase.retainRemoteCompletedEffects(
        session: session,
        operations: operations,
        expectedAccountBindingHashHex: profile.accountBindingHashHex,
      );
      await _module.uiLog.log(
        'bingx.remote_session.effects_restored',
        'session_operation_id=${session.operationId} '
            'count=${operations.length} effect=false',
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
                      subtitle: Text(
                        'Capsule-scoped status and emergency controls',
                      ),
                    ),
                    ...profiles.map(
                      (profile) => _RemoteRunnerProfileTile(
                        profile: profile,
                        loadStatus:
                            () => _module.remoteRunnerProvisioning.status(
                              profile,
                            ),
                        pause:
                            () =>
                                _module.remoteRunnerProvisioning.pause(profile),
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

  Future<void> _exportSignedRemoteDeterministicSession() async {
    if (_exportingRemoteMandate) return;
    final mandate = _tradingMandate;
    if (!_droneEnabled ||
        mandate == null ||
        !mandate.isActiveAt(DateTime.now().toUtc())) {
      await _showSnack('An active bounded trading mandate is required.');
      return;
    }
    final selectionNotice = tradingMandateSelectionNotice(
      mandate: mandate,
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
    final credentials = await _loadCredentials();
    if (credentials == null) {
      await _showSnack('Save BingX Futures credentials first.');
      return;
    }
    final leverage = await _module.exchangeService.getLeverage(
      credentials: credentials,
      symbol: mandate.symbol,
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
        'symbol=${mandate.symbol} '
            'sl_pct=${_stopLossPercent.toStringAsFixed(2)} '
            'long_leverage=${leverage.longLeverage ?? "-"} '
            'short_leverage=${leverage.shortLeverage ?? "-"} effect=false',
      );
      await _showSnack(leverageNotice, seconds: 6);
      return;
    }
    final accountBindingHashHex = _module.accountBindingHashHex(credentials);
    final runner = await _selectRemoteRunner(
      mandate,
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
    final expiresAtUtc = DateTime.tryParse(mandate.expiresAtUtc)?.toUtc();
    if (expiresAtUtc == null) {
      await _showSnack('The active mandate has an invalid expiry.');
      return;
    }
    final remainingSeconds = expiresAtUtc.difference(startsAtUtc).inSeconds;
    final maxCycles = ((remainingSeconds - 1) ~/ intervalSeconds + 1).clamp(
      1,
      BingxFuturesRemoteMandateAdmission.maxSessionCycles,
    );
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Authorize VPS trading session?'),
            content: Text(
              'Symbol: ${mandate.symbol}\n'
              'Mode: ${mandate.testOrder ? "test" : "live"}\n'
              'Check interval: 5 minutes\n'
              'First check: ${startsAtUtc.toIso8601String()}\n'
              'Activate before: ${firstCycleDeadlineUtc.toIso8601String()}\n'
              'Maximum checks: $maxCycles\n'
              'Maximum exchange effects: ${mandate.maxEffects}\n'
              'Exchange leverage: long ${leverage.longLeverage}x, '
              'short ${leverage.shortLeverage}x\n'
              'Stop loss: ${_stopLossPercent.toStringAsFixed(1)}%\n'
              'Authorized reads: balance, positions, realized PnL, and '
              '${mandate.symbol} leverage and margin mode.\n'
              'Expires: ${mandate.expiresAtUtc}\n\n'
              'The VPS may evaluate only this signed strategy and mandate. '
              'Every exchange attempt remains bounded by the existing effect journal.',
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
          mandate: mandate,
          runnerKeyId: runner.runnerKeyId,
          strategyPolicy:
              BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
                stopLossPercent: _stopLossPercent,
                minimumRiskReward: _takeProfitRiskReward,
              ),
          startsAtUtc: startsAtUtc,
          intervalSeconds: intervalSeconds,
          maxCycles: maxCycles,
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
    _updateState(() => _exportingRemoteMandate = true);
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
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_session.deploy.error',
        'operation_id=${admission.operationId} error=$error effect=false',
      );
      await _showSnack('Remote Runner activation failed: $error', seconds: 5);
    } finally {
      if (mounted) _updateState(() => _exportingRemoteMandate = false);
    }
  }

  Future<String> _revokeRemoteSession(
    BingxFuturesRemoteRunnerProfile profile,
  ) async {
    final canonicalSession = await _module.remoteRunnerProvisioning
        .loadActiveSession(profile);
    if (canonicalSession == null) {
      throw StateError('This Runner has no locally retained active session.');
    }
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
        session.runnerKeyId != profile.runnerKeyId) {
      throw StateError('The retained VPS session is not authentic.');
    }
    final revocation = BingxFuturesRemoteSessionRevocation.issue(
      session: session,
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
      'session_operation_id=${session.operationId} '
          'revocation_id=${revocation.revocationId} '
          'runner_key_id=${session.runnerKeyId} effect=false',
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
                          'Stop loss: ${_stopLossPercent.toStringAsFixed(1)}% · '
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
                            final compatible =
                                profile.accountBindingHashHex ==
                                accountBindingHashHex;
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
                                compatible
                                    ? 'Ready · ${profile.runnerBuildId}'
                                    : 'Bound to another BingX account',
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

String tradingRemoteRunnerStatusLabel(String raw) {
  const unknown = 'Runner status unknown. Refresh to retry.';
  if (raw.trim().isEmpty || raw.length > 4096) return unknown;
  final fields = <String, String>{};
  for (final token in raw.trim().split(RegExp(r'\s+'))) {
    final separator = token.indexOf('=');
    if (separator <= 0) return unknown;
    final key = token.substring(0, separator);
    if (fields.containsKey(key)) return unknown;
    fields[key] = token.substring(separator + 1);
  }
  final process = switch (fields['active']) {
    'active' => 'Runner running',
    'inactive' => 'Runner paused',
    'failed' => 'Runner failed',
    _ => null,
  };
  if (process == null) return unknown;
  final startup = switch (fields['enabled']) {
    'enabled' =>
      'WARNING: autostart enabled — a VPS reboot may start the Runner.',
    'enabled-runtime' => 'WARNING: runtime startup activation is enabled.',
    'linked' || 'linked-runtime' || 'disabled' => 'Autostart: not enabled.',
    'masked' || 'masked-runtime' => 'Startup blocked: service masked.',
    _ => 'Autostart status unknown — pause persistence is not verified.',
  };
  final state = fields['session_state'];
  if (state == null || state == 'unavailable') {
    return '$process\n$startup\nSession details unavailable on this Runner.';
  }
  if (!{'active', 'completed', 'stopped', 'expired'}.contains(state)) {
    return unknown;
  }
  final cycles = int.tryParse(fields['cycles'] ?? '');
  final effects = int.tryParse(fields['effects'] ?? '');
  if (cycles == null ||
      effects == null ||
      cycles < 0 ||
      cycles > 288 ||
      effects < 0 ||
      effects > cycles) {
    return unknown;
  }
  final outcome = fields['last_outcome'];
  String result;
  if (outcome == 'none' && cycles == 0) {
    result = 'No completed check yet';
  } else if (cycles > 0 &&
      outcome != null &&
      RegExp(r'^blocked:[a-z0-9_]{1,96}$').hasMatch(outcome)) {
    result = 'No order: ${outcome.substring(8).replaceAll('_', ' ')}';
  } else if (cycles > 0 &&
      effects > 0 &&
      outcome != null &&
      RegExp(
        r'^effect:(succeeded|unresolved|terminal_failure):test=(true|false)$',
      ).hasMatch(outcome)) {
    final status = outcome.split(':')[1];
    result = switch (status) {
      'succeeded' =>
        outcome.endsWith('true')
            ? 'Test request confirmed — not a live order'
            : 'Provider receipt confirmed',
      'unresolved' => 'Outcome unresolved — reconciliation required',
      _ => 'Provider execution failed',
    };
  } else {
    return unknown;
  }
  final last = fields['last_scheduled_check'];
  final next = fields['next_check'];
  bool validTime(String? value) =>
      value != null &&
      RegExp(r'^\d{4}-\d{2}-\d{2}T.*(?:Z|\+00:00)$').hasMatch(value) &&
      DateTime.tryParse(value) != null;
  if ((cycles == 0 ? last != 'none' : !validTime(last)) ||
      (state == 'active' ? !validTime(next) : next != 'none')) {
    return unknown;
  }
  return [
    '$process · Session $state',
    startup,
    'Checks: $cycles · Exchange attempts: $effects',
    'Last retained result: $result',
    if (cycles > 0) 'Last completed check slot: $last',
    if (state == 'active' && fields['active'] == 'active')
      'Next scheduled check: $next (not guaranteed execution)',
    if (state == 'active' && fields['active'] != 'active')
      'No checks run while the Runner is paused or failed.',
  ].join('\n');
}

class _RemoteRunnerProfileTile extends StatefulWidget {
  final BingxFuturesRemoteRunnerProfile profile;
  final Future<String> Function() loadStatus;
  final Future<String> Function() pause;
  final Future<String> Function() revoke;
  final Future<String> Function() remove;

  const _RemoteRunnerProfileTile({
    required this.profile,
    required this.loadStatus,
    required this.pause,
    required this.revoke,
    required this.remove,
  });

  @override
  State<_RemoteRunnerProfileTile> createState() =>
      _RemoteRunnerProfileTileState();
}

class _RemoteRunnerProfileTileState extends State<_RemoteRunnerProfileTile> {
  late Future<String> _status = widget.loadStatus();
  var _pausing = false;
  var _removed = false;
  String? _actionError;

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
                ? Future<String>.value('Remote Runner removed')
                : widget.loadStatus();
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
                        ? 'Remote Runner removed'
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
                OutlinedButton.icon(
                  onPressed:
                      _pausing
                          ? null
                          : () => setState(() => _status = widget.loadStatus()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _pausing ? null : () => _runAction(widget.pause),
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                  label: Text(_pausing ? 'Pausing' : 'Pause'),
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
                                          'Revoke VPS Session?',
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
                                              'Revoke VPS Session',
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
                  label: const Text('Revoke VPS Session'),
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
                                          'Remove Remote Runner?',
                                        ),
                                        content: Text(
                                          'This pauses and removes the exact Runner from '
                                          '${widget.profile.host}:${widget.profile.port}, '
                                          'then deletes its Capsule-local SSH identity. '
                                          'It does not delete the VPS.',
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
                                              'Remove exact Runner',
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
                  label: Text(_removed ? 'Removed' : 'Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
