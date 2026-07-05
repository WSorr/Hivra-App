import 'capsule_persistence_models.dart';

class CapsuleDiagnosticsReport {
  final CapsuleBootstrapReport bootstrap;
  final CapsuleTraceReport trace;

  const CapsuleDiagnosticsReport({
    required this.bootstrap,
    required this.trace,
  });
}

class CapsuleDiagnosticsService {
  final Future<CapsuleBootstrapReport> Function() _diagnoseBootstrap;
  final Future<CapsuleTraceReport> Function() _diagnoseTrace;

  const CapsuleDiagnosticsService({
    required Future<CapsuleBootstrapReport> Function() diagnoseBootstrap,
    required Future<CapsuleTraceReport> Function() diagnoseTrace,
  })  : _diagnoseBootstrap = diagnoseBootstrap,
        _diagnoseTrace = diagnoseTrace;

  Future<CapsuleDiagnosticsReport> inspect() async {
    final bootstrap = await _diagnoseBootstrap();
    final trace = await _diagnoseTrace();
    return CapsuleDiagnosticsReport(
      bootstrap: bootstrap,
      trace: trace,
    );
  }
}
