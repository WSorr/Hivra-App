import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_runtime_service.dart';
import '../utils/hivra_id_format.dart';

class TransportsScreen extends StatelessWidget {
  final AppRuntimeService runtime;
  final bool embedded;

  const TransportsScreen({
    super.key,
    required this.runtime,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final rootKey = _safeFormat(
      runtime.capsuleRootPublicKey(),
      HivraIdFormat.formatCapsuleKeyBytes,
    );
    final nostrKey = _safeFormat(
      runtime.capsuleNostrPublicKey(),
      HivraIdFormat.formatNostrKeyBytes,
    );

    final content = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _HeroPanel(),
        const SizedBox(height: 16),
        _TransportAdapterCard(
          title: 'Nostr',
          status: 'Mounted',
          statusColor: const Color(0xFF6EDB7F),
          icon: Icons.hub_rounded,
          description:
              'Built-in host adapter for capsule delivery. It is not a WASM drone and does not define ledger meaning.',
          facts: [
            _TransportFact(label: 'Layer', value: 'Host transport adapter'),
            _TransportFact(label: 'Effects', value: 'Network, relay, retry'),
            _TransportFact(label: 'Capsule root', value: rootKey),
            _TransportFact(label: 'Nostr endpoint', value: nostrKey),
          ],
        ),
        const SizedBox(height: 12),
        const _TransportAdapterCard(
          title: 'Matrix',
          status: 'Planned',
          statusColor: Color(0xFFFFC76A),
          icon: Icons.forum_rounded,
          description:
              'Future host adapter. It must carry signed capsule envelopes without becoming product logic.',
          facts: [
            _TransportFact(label: 'Layer', value: 'Host transport adapter'),
            _TransportFact(label: 'State', value: 'Not mounted'),
          ],
        ),
        const SizedBox(height: 12),
        const _TransportAdapterCard(
          title: 'Bluetooth LE / Local Mesh',
          status: 'Planned',
          statusColor: Color(0xFFFFC76A),
          icon: Icons.bluetooth_connected_rounded,
          description:
              'Future offline/nearby delivery path. It must remain below Core and above platform networking.',
          facts: [
            _TransportFact(label: 'Layer', value: 'Host transport adapter'),
            _TransportFact(label: 'State', value: 'Not mounted'),
          ],
        ),
        const SizedBox(height: 18),
        const _BoundaryPanel(),
      ],
    );

    if (embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Transports')),
      body: content,
    );
  }

  static String _safeFormat(
    Uint8List? bytes,
    String Function(Uint8List bytes) formatter,
  ) {
    if (bytes == null || bytes.length != 32) return 'Unavailable';
    try {
      return formatter(bytes);
    } catch (_) {
      return 'Unavailable';
    }
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10221A), Color(0xFF111820)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF263A31)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cable_rounded, color: Color(0xFF6EDB7F), size: 28),
              SizedBox(width: 10),
              Text(
                'Transport Layer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Transports are system adapters. They deliver signed capsule envelopes; they do not run WASM drone logic, mutate ledger truth, or bypass consensus guards.',
            style: TextStyle(color: Color(0xFFB8C1CC), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _TransportAdapterCard extends StatelessWidget {
  final String title;
  final String status;
  final Color statusColor;
  final IconData icon;
  final String description;
  final List<_TransportFact> facts;

  const _TransportAdapterCard({
    required this.title,
    required this.status,
    required this.statusColor,
    required this.icon,
    required this.description,
    required this.facts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF29313B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: statusColor, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(color: Color(0xFF9FA8B6), height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: facts
                .map(
                  (fact) => _FactChip(label: fact.label, value: fact.value),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  final String label;
  final String value;

  const _FactChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2029),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E3743)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7F8A98),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            HivraIdFormat.short(value, head: 18, tail: 8),
            style: const TextStyle(
              color: Color(0xFFD8DEE8),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundaryPanel extends StatelessWidget {
  const _BoundaryPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161319),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF332A35)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Boundary contract',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 10),
          _BoundaryRow(
            icon: Icons.south_rounded,
            text:
                'Dependencies stay downward: UI -> app service -> FFI -> adapter.',
          ),
          _BoundaryRow(
            icon: Icons.gavel_rounded,
            text:
                'Ledger remains the source of truth; transport only delivers bytes.',
          ),
          _BoundaryRow(
            icon: Icons.extension_off_rounded,
            text: 'WASM drones never get direct network or keychain access.',
          ),
        ],
      ),
    );
  }
}

class _BoundaryRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BoundaryRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFB89CFF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFB8C1CC), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportFact {
  final String label;
  final String value;

  const _TransportFact({required this.label, required this.value});
}
