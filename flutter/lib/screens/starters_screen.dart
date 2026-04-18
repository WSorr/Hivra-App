import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import '../services/app_runtime_service.dart';
import '../services/invitation_delivery_service.dart';
import '../services/invitation_intent_handler.dart';
import '../services/ui_event_log_service.dart';
import '../services/ui_feedback_service.dart';
import '../utils/hivra_id_format.dart';

class StartersScreen extends StatefulWidget {
  final AppRuntimeService runtime;
  final String activeCapsuleHex;
  final Future<void> Function()? onLedgerChanged;

  const StartersScreen({
    super.key,
    required this.runtime,
    required this.activeCapsuleHex,
    this.onLedgerChanged,
  });

  @override
  State<StartersScreen> createState() => _StartersScreenState();
}

class _StartersScreenState extends State<StartersScreen> {
  final InvitationDeliveryService _delivery = const InvitationDeliveryService();
  final UiEventLogService _uiLog = const UiEventLogService();
  late final InvitationIntentHandler _intents;
  List<Map<String, dynamic>> _slots = const [];

  @override
  void initState() {
    super.initState();
    _intents = widget.runtime.invitationIntents;
    _loadSlots();
  }

  void _loadSlots() {
    final stateManager = widget.runtime.stateManager;
    stateManager.refresh();
    final starterSlots = stateManager.state.starterSlots;

    final slots = <Map<String, dynamic>>[];
    for (int i = 0; i < 5; i++) {
      final slotState = i < starterSlots.length ? starterSlots[i] : null;
      final id = slotState?.starterId;

      slots.add({
        'index': i,
        'occupied': slotState?.occupied ?? false,
        'type': slotState?.kind ?? 'Unknown',
        'starterId': id != null ? _formatStarterId(id) : null,
        'starterIdRaw': id,
        'locked': slotState?.locked ?? false,
      });
    }

    if (!mounted) return;
    setState(() {
      _slots = slots;
    });
  }

  String _formatStarterId(Uint8List id) {
    return HivraIdFormat.short(HivraIdFormat.formatStarterIdBytes(id));
  }

  Future<void> _showInviteDialog(Map<String, dynamic> slot) async {
    final TextEditingController pubkeyController = TextEditingController();
    String? formError;
    bool isSending = false;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Invite with ${slot['type']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter recipient public key:'),
              const SizedBox(height: 8),
              const Text(
                'Supports: h... (if imported) or another supported delivery address',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pubkeyController,
                decoration: InputDecoration(
                  hintText: 'Public key',
                  border: const OutlineInputBorder(),
                  errorText: formError,
                ),
                maxLines: 2,
                onChanged: (_) {
                  if (formError != null) {
                    setDialogState(() => formError = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      final input = pubkeyController.text.trim();
                      if (input.isEmpty) {
                        setDialogState(
                          () => formError =
                              'Please enter a capsule address or delivery address',
                        );
                        return;
                      }

                      setDialogState(() {
                        isSending = true;
                      });

                      final resolution =
                          await _delivery.resolveRecipientAddress(
                        input,
                        selfRootKey: widget.runtime.capsuleRootPublicKey(),
                        selfNostrKey: widget.runtime.capsuleNostrPublicKey(),
                      );
                      if (!context.mounted) return;
                      if (!resolution.isSuccess) {
                        unawaited(_uiLog.log(
                          'starters.send.resolve_failed',
                          resolution.errorMessage ??
                              'Could not resolve recipient address',
                        ));
                        setDialogState(
                          () {
                            formError = resolution.errorMessage ??
                                'Could not resolve recipient address';
                            isSending = false;
                          },
                        );
                        return;
                      }

                      final slotIndex =
                          slot['index'] is int ? slot['index'] as int : -1;
                      if (slotIndex < 0 || slotIndex > 4) {
                        unawaited(
                          _uiLog.log(
                            'starters.send.invalid_slot',
                            'slot=$slotIndex input=$input',
                          ),
                        );
                        setDialogState(() {
                          formError = 'Invalid starter slot';
                          isSending = false;
                        });
                        return;
                      }

                      final startedAt = DateTime.now();
                      final operationCapsuleHex = widget.activeCapsuleHex;
                      InvitationIntentResult? sendResult;
                      try {
                        unawaited(_uiLog.log(
                          'starters.send.request',
                          'slot=$slotIndex peer=$input',
                        ));

                        sendResult = await _intents.sendInvitation(
                          resolution.transportRecipient!,
                          slotIndex,
                          capsuleHex: operationCapsuleHex,
                        );
                        final result = sendResult;
                        unawaited(_uiLog.log(
                          'starters.send.result',
                          'slot=$slotIndex code=${result.code} message=${result.message}',
                        ));
                        if (!result.isSuccess) {
                          if (context.mounted) {
                            setDialogState(() {
                              formError = result.message;
                              isSending = false;
                            });
                          }
                          if (mounted) {
                            UiFeedbackService.showSnackBar(
                              this.context,
                              result.message,
                              source: 'starters.send',
                              duration: const Duration(seconds: 3),
                              enableCopy: false,
                            );
                          }
                          return;
                        }

                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        if (!mounted) return;
                        final peerPreview = input.length <= 8
                            ? input
                            : '${input.substring(0, 8)}...';
                        UiFeedbackService.showSnackBar(
                          this.context,
                          'Invitation sent to $peerPreview. Receiver should pull to refresh Invitations.',
                          source: 'starters.send',
                          duration: const Duration(seconds: 5),
                          enableCopy: false,
                        );

                        setState(() {
                          slot['locked'] = true;
                        });
                        _loadSlots();
                        await widget.onLedgerChanged?.call();
                      } catch (e) {
                        unawaited(_uiLog.log('starters.send.exception', '$e'));
                        if (mounted) {
                          UiFeedbackService.showSnackBar(
                            this.context,
                            'Failed to send: $e',
                            source: 'starters.send',
                            duration: const Duration(seconds: 3),
                            enableCopy: false,
                          );
                        }
                        if (context.mounted) {
                          setDialogState(() {
                            isSending = false;
                          });
                        }
                      } finally {
                        final elapsedMs =
                            DateTime.now().difference(startedAt).inMilliseconds;
                        unawaited(
                          _uiLog.log(
                            'starters.send.finally',
                            'slot=$slotIndex elapsedMs=$elapsedMs resultCode=${sendResult?.code ?? 'none'} contextMounted=${context.mounted} widgetMounted=$mounted',
                          ),
                        );
                        if (context.mounted && isSending) {
                          setDialogState(() {
                            isSending = false;
                          });
                        }
                      }
                    },
              child: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Invitation'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadSlots();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) {
          final slot = _slots[index];
          return _buildSlotCard(slot);
        },
      ),
    );
  }

  Widget _buildSlotCard(Map<String, dynamic> slot) {
    final bool occupied = slot['occupied'];
    final String type = slot['type'];
    final String displayType = occupied ? type : 'Empty';
    final bool locked = slot['locked'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getTypeColor(displayType).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _getTypeColor(displayType)),
                  ),
                  child: Text(
                    displayType,
                    style: TextStyle(
                      color: _getTypeColor(displayType),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Slot ${slot['index'] + 1}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (occupied) ...[
              Row(
                children: [
                  const Icon(Icons.fingerprint, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ID: ${slot['starterId']}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    locked ? Icons.lock : Icons.lock_open,
                    size: 16,
                    color: locked ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    locked ? 'Locked (invitation pending)' : 'Available',
                    style: TextStyle(
                      color: locked ? Colors.orange : Colors.green,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'Empty slot - ready to receive',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (occupied && !locked)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showInviteDialog(slot),
                  icon: const Icon(Icons.send),
                  label: const Text('Invite'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Juice':
        return Colors.orange;
      case 'Spark':
        return Colors.yellow;
      case 'Seed':
        return Colors.green;
      case 'Pulse':
        return Colors.red;
      case 'Kick':
        return Colors.blue;
      case 'Empty':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
