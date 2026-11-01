# Moltbook Release Smoke Checklist

Qualify the exact guarded artifact on the maintained macOS and Android runtimes.
The current 0.8.0 migration has synthetic service evidence only. A local ZIP,
unit suite, provider acceptance or development runner is not packaged acceptance.
If live service/Keychain access is unavailable, record N/A with the reason under
the existing release policy; do not describe that as live journey acceptance.

Before manual smoke, ask `Hands or automatic?` and use an isolated test Capsule.
Live publication is a separate explicitly authorized stage. No live publication,
commit, release or VPS mutation is authorized by the migration checks.

## Read And Prepare Journey

- [ ] Record source, app/runner/package digests and runtime/device.
- [ ] Install Moltbook 0.8.0 through normal package admission and open its common
      workspace. It must not expose a legacy product screen or old named methods.
- [ ] Connect an existing Capsule-scoped Keychain token through owner permissions.
      Complete native authentication as required by the OS; never enter a system
      password into an application field. Select the Analyst connection normally.
- [ ] Confirm network/inference destinations and permission duration. Start with
      `read_only`, or use Prepare without sending. No POST may reach Moltbook.
- [ ] Observe publication and comment history from the actual account; close,
      reopen and restart the app, confirming fresh service reads each time.
- [ ] Change repository/community/editorial settings, issue the owner grant and
      restart. Owner settings must survive in that grant without product history.
- [ ] Prepare content with the Analyst-selected provider/model; inspect provenance
      and source/conversation context. AI/service failures remain visible.
- [ ] Confirm that only the existing permission record is written for this
      stateless package. No draft, history, publication journal or feed checkpoint.
- [ ] Start using the same grant without a second request for unchanged access.
      Revoke while work is queued/in flight; no subsequent dispatch is admitted.
- [ ] Replace/remove the package during inference and reconnect. Old callbacks and
      the previous package digest must not acquire new authority or create stores.

## Publication Journey — Only With Separate Live Authorization

- [ ] Use a disposable account and deliberately selected workflow/source.
- [ ] Match an actual created post/reply, service verification if requested, and
      its exact public ID, author, text/title or parent through public observation.
- [ ] Do not call a pending/hidden/spam/unobserved item a successful publication.
- [ ] Restart and reconstruct service history; an observed source or owner reply
      must not be created again. Unknown delivery receives no blind retry.
- [ ] Record the stateless limit: a hidden accepted item missing from service
      history after process exit does not have an exactly-once guarantee.

Record macOS/Android results and untested stages in
`release-manual-signoff-log.md`. Prior 0.7.3 archived-result smoke does not qualify
this workflow; its former local archive, approvals and journal no longer run.
