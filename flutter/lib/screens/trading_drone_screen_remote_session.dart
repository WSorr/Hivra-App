part of 'trading_drone_screen.dart';

extension _TradingDroneRemoteSession on _TradingDroneScreenState {
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
    if (!Platform.isMacOS) {
      await _showSnack(
        'Remote session export is currently available on macOS.',
      );
      return;
    }
    final runnerKeyId = await _selectRemoteRunnerKeyId(mandate);
    if (runnerKeyId == null) return;
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
          runnerKeyId: runnerKeyId,
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
    final targetPath = await HivraFilePickerService.saveJsonDocument(
      suggestedName:
          'trading-remote-session-${admission.operationId.substring(0, 16)}.json',
      confirmButtonText: 'Export session',
    );
    if (targetPath == null || targetPath.trim().isEmpty) return;
    final target = File(targetPath.trim());
    if (await target.exists()) {
      await _showSnack('The remote session artifact already exists.');
      return;
    }
    _updateState(() => _exportingRemoteMandate = true);
    try {
      await const AtomicFileWriteService().writeString(
        target,
        admission.canonicalJson,
      );
      await _module.uiLog.log(
        'bingx.remote_session.exported',
        'operation_id=${admission.operationId} '
            'runner_key_id=${admission.runnerKeyId} '
            'starts_at_utc=${startsAtUtc.toIso8601String()} '
            'first_cycle_deadline_utc=${firstCycleDeadlineUtc.toIso8601String()} '
            'max_cycles=$maxCycles interval_seconds=$intervalSeconds effect=false',
      );
      if (mounted) {
        await _showPreparedSessionApplyInstructions(
          runnerKeyId: admission.runnerKeyId,
          mandateFileName: target.path.split(Platform.pathSeparator).last,
          startsAtUtc: startsAtUtc,
          firstCycleDeadlineUtc: firstCycleDeadlineUtc,
        );
      }
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_session.export.error',
        'operation_id=${admission.operationId} error=$error effect=false',
      );
      await _showSnack('Remote session export failed.');
    } finally {
      if (mounted) _updateState(() => _exportingRemoteMandate = false);
    }
  }

  Future<void> _showPreparedSessionApplyInstructions({
    required String runnerKeyId,
    required String mandateFileName,
    required DateTime startsAtUtc,
    required DateTime firstCycleDeadlineUtc,
  }) async {
    final command = tradingPreparedSessionApplyCommand(
      runnerKeyId: runnerKeyId,
      mandateFileName: mandateFileName,
    );
    final activationCommand = tradingPreparedSessionActivationCommand(
      runnerKeyId: runnerKeyId,
    );
    final runCommand = tradingPreparedSessionRunCommand(
      runnerKeyId: runnerKeyId,
    );
    final serviceEnableCommand = tradingPreparedSessionServiceEnableCommand(
      runnerKeyId: runnerKeyId,
    );
    final servicePauseCommand = tradingPreparedSessionServicePauseCommand();
    final serviceStatusCommand = tradingPreparedSessionServiceStatusCommand();
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Session ready for VPS'),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. Transfer the signed session file to the already verified '
                      'Runner, then apply it from tools/trading:',
                    ),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          command,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'BingX credentials are entered in the hidden VPS prompt. '
                      'The command prepares the credential and exact signed '
                      'session but leaves the Runner disabled and inactive.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Provision and activate before '
                      '${firstCycleDeadlineUtc.toIso8601String()}. The first '
                      'check starts at ${startsAtUtc.toIso8601String()}. If '
                      'that signed window is missed, export a fresh session.',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '2. After Apply succeeds, explicitly activate only that '
                      'prepared session:',
                    ),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          activationCommand,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Activation creates bounded local session state only. It '
                      'does not start scheduling or submit an exchange order.',
                    ),
                    const SizedBox(height: 16),
                    const Text('3. Enable continuous VPS operation:'),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          serviceEnableCommand,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The service resumes after a VPS reboot only while the '
                      'same signed session remains valid. It never retries a '
                      'failed cycle or catches up missed cycles.',
                    ),
                    const SizedBox(height: 16),
                    const Text('Service status and explicit pause:'),
                    const SizedBox(height: 12),
                    SelectableText(
                      '$serviceStatusCommand\n$servicePauseCommand',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Diagnostic foreground run (optional):'),
                    const SizedBox(height: 12),
                    SelectableText(
                      runCommand,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Future<void> _exportSignedRemoteSessionRevocation() async {
    if (_exportingRemoteRevocation) return;
    final selected = await HivraFilePickerService.openJsonDocument();
    if (selected == null) return;
    final session = BingxFuturesRemoteMandateAdmission.parseAndVerify(
      untrustedWireBytes: await selected.readAsBytes(),
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
    if (session == null || !session.isDeterministicSession) {
      await _showSnack('Select one valid signed VPS session artifact.');
      return;
    }
    final activeRoot = _module.orderTrackingStore.activeCapsuleRootHex;
    if (activeRoot == null || session.mandate.capsuleRootHex != activeRoot) {
      await _showSnack('The selected session belongs to another Capsule.');
      return;
    }
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Revoke this VPS session?'),
            content: Text(
              'Session: ${session.operationId.substring(0, 16)}…\n'
              'Runner: ${session.runnerKeyId.substring(0, 16)}…\n'
              'Symbol: ${session.mandate.symbol}\n\n'
              'This immediately pauses local trading and creates a signed '
              'stop file. The VPS stops only after that file is applied to '
              'the exact runner.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Create stop file'),
              ),
            ],
          ),
    );
    if (approved != true) return;
    final revocation = BingxFuturesRemoteSessionRevocation.issue(
      session: session,
      revokedAtUtc: DateTime.now().toUtc(),
      signCommitment: _module.signRootCommitment,
    );
    if (revocation == null ||
        BingxFuturesRemoteSessionRevocation.parseAndVerify(
              untrustedWireBytes: utf8.encode(revocation.canonicalJson),
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
      await _showSnack('Capsule could not sign the session stop file.');
      return;
    }
    final targetPath = await HivraFilePickerService.saveJsonDocument(
      suggestedName:
          'trading-session-stop-${session.operationId.substring(0, 16)}.json',
      confirmButtonText: 'Export stop file',
    );
    if (targetPath == null || targetPath.trim().isEmpty) return;
    final target = File(targetPath.trim());
    if (await target.exists()) {
      await _showSnack('The session stop file already exists.');
      return;
    }
    _updateState(() => _exportingRemoteRevocation = true);
    try {
      await const AtomicFileWriteService().writeString(
        target,
        revocation.canonicalJson,
      );
      var localPausePersisted = true;
      if (_droneEnabled) {
        try {
          localPausePersisted = await _changeDroneEnabled(
            false,
            requirePersistence: true,
          );
        } catch (error) {
          localPausePersisted = false;
          await _module.uiLog.log(
            'bingx.remote_session.revocation.local_pause.error',
            'session_operation_id=${session.operationId} error=$error effect=false',
          );
        }
      }
      await _module.uiLog.log(
        'bingx.remote_session.revocation.exported',
        'session_operation_id=${session.operationId} '
            'revocation_id=${revocation.revocationId} '
            'runner_key_id=${session.runnerKeyId} effect=false',
      );
      await _showSnack(
        localPausePersisted
            ? 'Signed stop file exported. Apply it to the exact VPS runner.'
            : 'Stop file exported, but local pause was not persisted. Pause '
                'the Drone and apply the file to the exact VPS runner.',
        seconds: 5,
      );
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_session.revocation.export.error',
        'session_operation_id=${session.operationId} error=$error effect=false',
      );
      await _showSnack('VPS session stop export failed.');
    } finally {
      if (mounted) _updateState(() => _exportingRemoteRevocation = false);
    }
  }

  Future<String?> _selectRemoteRunnerKeyId(
    BingxFuturesTradingMandate mandate,
  ) async {
    final expectedCapsuleRootHex = _module.activeCapsuleRootHex();
    if (expectedCapsuleRootHex == null) {
      await _showSnack('Active Capsule is unavailable.');
      return null;
    }
    String? errorText;
    var importing = false;
    BingxFuturesRemoteRunnerBinding? selectedBinding =
        await _module.remoteRunnerIdentity.loadVerifiedBinding();
    if (!mounted) return null;
    final result = await showDialog<String>(
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
                                  importing
                                      ? null
                                      : () async {
                                        setDialogState(() {
                                          importing = true;
                                          errorText = null;
                                        });
                                        try {
                                          final path =
                                              await HivraFilePickerService.selectDirectory(
                                                confirmButtonText:
                                                    'Verify runner anchor',
                                              );
                                          if (path == null) return;
                                          final binding = await _module
                                              .remoteRunnerIdentity
                                              .verifyAnchorDirectory(path);
                                          await _module.remoteRunnerIdentity
                                              .saveVerifiedBinding(
                                                binding,
                                                expectedCapsuleRootHex:
                                                    expectedCapsuleRootHex,
                                              );
                                          selectedBinding = binding;
                                        } on FormatException catch (error) {
                                          errorText = error.message;
                                        } catch (_) {
                                          errorText =
                                              'Runner key file could not be read.';
                                        } finally {
                                          if (context.mounted) {
                                            setDialogState(() {
                                              importing = false;
                                            });
                                          }
                                        }
                                      },
                              icon:
                                  importing
                                      ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.key_rounded),
                              label: const Text('Verify runner anchor'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          selectedBinding == null
                              ? 'No verified runner is bound to this Capsule.'
                              : 'Verified runner: '
                                  '${selectedBinding!.runnerKeyId.substring(0, 16)}…\n'
                                  'Build: ${selectedBinding!.runnerBuildId}\n'
                                  'Plugin: ${selectedBinding!.pluginVersion}',
                        ),
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
                          importing
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          importing
                              ? null
                              : () {
                                final runnerKeyId =
                                    selectedBinding?.runnerKeyId;
                                if (runnerKeyId == null) {
                                  setDialogState(() {
                                    errorText =
                                        'Verify one runner anchor first.';
                                  });
                                  return;
                                }
                                Navigator.of(dialogContext).pop(runnerKeyId);
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
}
