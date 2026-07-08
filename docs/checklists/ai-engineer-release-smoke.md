# AI Engineer Release Smoke Checklist

Use this checklist for macOS release-candidate smoke before publishing builds
that include Capsule Analyst developer/AI tooling.

## Scope

- [ ] Platform is macOS release build, not debug run.
- [ ] Android smoke is deferred to the Android release checklist unless this is
      an Android release candidate.
- [ ] AI output is treated as advisory and unverified until gates are run.

## Capsule Analyst

- [ ] Capsule Analyst opens from Settings.
- [ ] Capsule snapshot renders without mutating capsule state.
- [ ] Copy snapshot produces a redacted payload only.

## Scoped AI Analyst

- [ ] Inference provider can be selected explicitly before submission.
- [ ] OpenAI/Gemini API key save/clear uses provider-isolated secure storage.
- [ ] Outbound preview is shown before provider submission.
- [ ] Provider failure leaves capsule ledger, plugin registry, and files unchanged.

## Plugin Auditor

- [ ] Installed plugin package audit renders package digest, ABI, entry export,
      and capability evidence.
- [ ] Selected plugin source audit remains read-only and cannot grant
      capabilities.
- [ ] Catalog digest/signature evidence is visible or explicitly marked missing.

## Developer Mode Boundary

- [ ] Developer Mode is disabled by default.
- [ ] Enabling Developer Mode is explicit for the current screen session.
- [ ] Developer Mode remains separate from normal user-facing Capsule
      Analyst.

## Workspace Preview

- [ ] Workspace preview scans only explicit local repository paths.
- [ ] Preview lists file metadata and hashes without uploading source contents.
- [ ] Denylisted secret paths are skipped.

## Selected Context

- [ ] Selected Context includes only user-selected allowlisted files.
- [ ] Changed files after preview are rejected before provider submission.
- [ ] Source/log/manifest text is labeled as untrusted prompt input.

## Hivra Engineer Advisory Ask

- [ ] Hivra Engineer outbound preview shows capsule snapshot hash, developer
      context hash, snippet count, and payload size.
- [ ] Hivra Engineer request includes no-mutation constraints.
- [ ] Hivra Engineer response is advisory only and does not claim files, git,
      ledger, plugin registry, tags, or releases were changed.

## Review Gate Integration

- [ ] AI advisory output is marked unverified until required gates are run.
- [ ] Required gates list includes `flutter analyze`.
- [ ] Required gates list includes `tools/review/review_all.sh`.
- [ ] AI output does not override review gates, release gates, or manual smoke.
