import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'consensus_processor.dart';

typedef ConsensusSignableReader = ConsensusSignableResult Function(
  String peerHex,
);

enum TemperatureOutcomeRule {
  above,
  below,
}

enum TemperatureContractOutcome {
  proposerWins,
  counterpartyWins,
  draw,
}

class TemperatureTomorrowContractSpec {
  final String pluginId;
  final String locationCode;
  final String targetDateUtc;
  final int thresholdDeciCelsius;
  final TemperatureOutcomeRule proposerRule;
  final bool drawOnEqual;

  const TemperatureTomorrowContractSpec({
    required this.pluginId,
    required this.locationCode,
    required this.targetDateUtc,
    required this.thresholdDeciCelsius,
    required this.proposerRule,
    required this.drawOnEqual,
  });

  factory TemperatureTomorrowContractSpec.fromManifestJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Plugin manifest must be a JSON object');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['schema'] != 'hivra.plugin.manifest') {
      throw const FormatException('Unsupported plugin manifest schema');
    }
    if (map['version'] != 1) {
      throw const FormatException('Unsupported plugin manifest version');
    }

    final pluginId = map['plugin_id']?.toString();
    if (pluginId == null || pluginId.isEmpty) {
      throw const FormatException('Manifest is missing plugin_id');
    }

    final contract = map['contract'];
    if (contract is! Map) {
      throw const FormatException('Manifest is missing contract section');
    }
    final contractMap = Map<String, dynamic>.from(contract);
    if (contractMap['kind'] != 'temperature_tomorrow_liechtenstein') {
      throw const FormatException('Unsupported contract kind');
    }

    final locationCode = contractMap['location_code']?.toString().trim();
    if (locationCode == null || locationCode.isEmpty) {
      throw const FormatException('Contract is missing location_code');
    }
    if (locationCode != 'LI') {
      throw const FormatException(
          'Only LI location is supported in v1 test contract');
    }

    final targetDateUtc = contractMap['target_date_utc']?.toString().trim();
    if (!_isDateOnlyUtc(targetDateUtc)) {
      throw const FormatException('target_date_utc must be YYYY-MM-DD');
    }

    final threshold = contractMap['threshold_deci_celsius'];
    final thresholdDeciCelsius =
        threshold is int ? threshold : int.tryParse('$threshold');
    if (thresholdDeciCelsius == null) {
      throw const FormatException('threshold_deci_celsius must be an integer');
    }

    final proposerRuleRaw = contractMap['proposer_rule']?.toString().trim();
    final proposerRule = switch (proposerRuleRaw) {
      'above' => TemperatureOutcomeRule.above,
      'below' => TemperatureOutcomeRule.below,
      _ => throw const FormatException(
          'proposer_rule must be either above or below',
        ),
    };

    final drawOnEqual = contractMap['draw_on_equal'] == true;

    return TemperatureTomorrowContractSpec(
      pluginId: pluginId,
      locationCode: locationCode,
      targetDateUtc: targetDateUtc!,
      thresholdDeciCelsius: thresholdDeciCelsius,
      proposerRule: proposerRule,
      drawOnEqual: drawOnEqual,
    );
  }
}

class TemperatureOracleObservation {
  final String sourceId;
  final String eventId;
  final String locationCode;
  final String targetDateUtc;
  final String recordedAtUtc;
  final int observedDeciCelsius;

  const TemperatureOracleObservation({
    required this.sourceId,
    required this.eventId,
    required this.locationCode,
    required this.targetDateUtc,
    required this.recordedAtUtc,
    required this.observedDeciCelsius,
  });
}

class TemperatureContractSettlement {
  final String pluginId;
  final String peerHex;
  final String locationCode;
  final String targetDateUtc;
  final int thresholdDeciCelsius;
  final int observedDeciCelsius;
  final TemperatureOutcomeRule proposerRule;
  final TemperatureContractOutcome outcome;
  final String winnerRole;
  final String canonicalJson;
  final String settlementHashHex;
  final String oracleSourceId;
  final String oracleEventId;
  final String oracleRecordedAtUtc;

  const TemperatureContractSettlement({
    required this.pluginId,
    required this.peerHex,
    required this.locationCode,
    required this.targetDateUtc,
    required this.thresholdDeciCelsius,
    required this.observedDeciCelsius,
    required this.proposerRule,
    required this.outcome,
    required this.winnerRole,
    required this.canonicalJson,
    required this.settlementHashHex,
    required this.oracleSourceId,
    required this.oracleEventId,
    required this.oracleRecordedAtUtc,
  });
}

class TemperatureContractExecutionResult {
  final TemperatureContractSettlement? settlement;
  final List<ConsensusBlockingFact> blockingFacts;

  const TemperatureContractExecutionResult({
    required this.settlement,
    required this.blockingFacts,
  });

  bool get isExecutable => settlement != null && blockingFacts.isEmpty;
}

class TemperatureTomorrowContractService {
  final ConsensusSignableReader _readSignable;

  const TemperatureTomorrowContractService({
    required ConsensusSignableReader readSignable,
  }) : _readSignable = readSignable;

  TemperatureContractExecutionResult execute({
    required String peerHex,
    required TemperatureTomorrowContractSpec contract,
    required TemperatureOracleObservation observation,
  }) {
    final signable = _readSignable(peerHex);
    if (!signable.isSignable) {
      return TemperatureContractExecutionResult(
        settlement: null,
        blockingFacts: signable.blockingFacts,
      );
    }

    final settlement = evaluateDeterministic(
      peerHex: peerHex,
      contract: contract,
      observation: observation,
    );
    return TemperatureContractExecutionResult(
      settlement: settlement,
      blockingFacts: const <ConsensusBlockingFact>[],
    );
  }

  TemperatureContractSettlement evaluateDeterministic({
    required String peerHex,
    required TemperatureTomorrowContractSpec contract,
    required TemperatureOracleObservation observation,
  }) {
    final location = contract.locationCode.trim().toUpperCase();
    final observationLocation = observation.locationCode.trim().toUpperCase();
    if (location != observationLocation) {
      throw const FormatException(
          'Oracle location does not match contract location');
    }
    if (contract.targetDateUtc != observation.targetDateUtc.trim()) {
      throw const FormatException(
          'Oracle target date does not match contract date');
    }
    if (!_isIsoInstant(observation.recordedAtUtc)) {
      throw const FormatException('Oracle recordedAtUtc must be ISO-8601 UTC');
    }

    final outcome = _resolveOutcome(
      observed: observation.observedDeciCelsius,
      threshold: contract.thresholdDeciCelsius,
      proposerRule: contract.proposerRule,
      drawOnEqual: contract.drawOnEqual,
    );

    final winnerRole = switch (outcome) {
      TemperatureContractOutcome.proposerWins => 'proposer',
      TemperatureContractOutcome.counterpartyWins => 'counterparty',
      TemperatureContractOutcome.draw => 'draw',
    };

    final canonical = jsonEncode({
      'schema_version': 1,
      'plugin_id': contract.pluginId,
      'contract_kind': 'temperature_tomorrow_liechtenstein',
      'peer_hex': peerHex,
      'location_code': location,
      'target_date_utc': contract.targetDateUtc,
      'threshold_deci_celsius': contract.thresholdDeciCelsius,
      'observed_deci_celsius': observation.observedDeciCelsius,
      'proposer_rule': contract.proposerRule.name,
      'outcome': outcome.name,
      'winner_role': winnerRole,
      'oracle_source_id': observation.sourceId,
      'oracle_event_id': observation.eventId,
      'oracle_recorded_at_utc': observation.recordedAtUtc,
    });
    final settlementHashHex = sha256.convert(utf8.encode(canonical)).toString();

    return TemperatureContractSettlement(
      pluginId: contract.pluginId,
      peerHex: peerHex,
      locationCode: location,
      targetDateUtc: contract.targetDateUtc,
      thresholdDeciCelsius: contract.thresholdDeciCelsius,
      observedDeciCelsius: observation.observedDeciCelsius,
      proposerRule: contract.proposerRule,
      outcome: outcome,
      winnerRole: winnerRole,
      canonicalJson: canonical,
      settlementHashHex: settlementHashHex,
      oracleSourceId: observation.sourceId,
      oracleEventId: observation.eventId,
      oracleRecordedAtUtc: observation.recordedAtUtc,
    );
  }

  TemperatureContractOutcome _resolveOutcome({
    required int observed,
    required int threshold,
    required TemperatureOutcomeRule proposerRule,
    required bool drawOnEqual,
  }) {
    if (observed == threshold) {
      if (drawOnEqual) return TemperatureContractOutcome.draw;
      return proposerRule == TemperatureOutcomeRule.above
          ? TemperatureContractOutcome.counterpartyWins
          : TemperatureContractOutcome.proposerWins;
    }

    final isAbove = observed > threshold;
    final proposerWins =
        proposerRule == TemperatureOutcomeRule.above ? isAbove : !isAbove;
    return proposerWins
        ? TemperatureContractOutcome.proposerWins
        : TemperatureContractOutcome.counterpartyWins;
  }
}

bool _isDateOnlyUtc(String? value) {
  if (value == null) return false;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
}

bool _isIsoInstant(String value) {
  try {
    final parsed = DateTime.parse(value);
    return parsed.isUtc;
  } catch (_) {
    return false;
  }
}
