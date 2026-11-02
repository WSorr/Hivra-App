import 'capsule_persistence_models.dart';

class CapsuleDiagnosticsReport {
  final CapsuleBootstrapReport? bootstrap;
  final CapsuleTraceReport? trace;
  final String? bootstrapError;
  final String? traceError;

  const CapsuleDiagnosticsReport({
    this.bootstrap,
    this.trace,
    this.bootstrapError,
    this.traceError,
  });
}

class CapsuleDiagnosticsService {
  final Future<CapsuleBootstrapReport> Function() _diagnoseBootstrap;
  final Future<CapsuleTraceReport> Function() _diagnoseTrace;

  const CapsuleDiagnosticsService({
    required Future<CapsuleBootstrapReport> Function() diagnoseBootstrap,
    required Future<CapsuleTraceReport> Function() diagnoseTrace,
  }) : _diagnoseBootstrap = diagnoseBootstrap,
       _diagnoseTrace = diagnoseTrace;

  Future<CapsuleDiagnosticsReport> inspect() async {
    CapsuleBootstrapReport? bootstrap;
    CapsuleTraceReport? trace;
    String? bootstrapError;
    String? traceError;
    try {
      bootstrap = await _diagnoseBootstrap();
    } catch (error) {
      bootstrapError = error.toString();
    }
    try {
      trace = await _diagnoseTrace();
    } catch (error) {
      traceError = error.toString();
    }
    return CapsuleDiagnosticsReport(
      bootstrap: bootstrap,
      trace: trace,
      bootstrapError: bootstrapError,
      traceError: traceError,
    );
  }
}
