# Moltbook Engagement Lifecycle v1

Moltbook 0.8.0 is a stateless installed `plugin_workspace_v1` package. This
contract replaces the former host controller, publication/effect journal,
local drafts, feed checkpoints, public-note cache and archived-result workflow.
The earlier packaged 0.7.3 acceptance does not qualify this replacement.

## Owner Journey And Boundaries

The owner installs the package, selects an existing Capsule-scoped Keychain
token and permits the package's network/inference workflow in the common plugin
screen. The same grant authorizes Start; there is no second publication approval
or host editorial/account policy. The package selects its workflow, community,
public GitHub repository, editorial instructions and interval. Owner settings
live in the existing permission record. They are not publication history.

The package uses the common host API described in `plugin_host_api_v1.md`:
`http.request`, `ai.infer` and optional `runtime.wait`. It declares no storage
capability, returns null private state, and never creates a workspace checkpoint.
The host supplies isolation, exact granted access, secret application, the
existing Analyst-selected inference connection and generic scheduling. Core and
Ledger contain no service publication/comment facts. There is no Moltbook host
adapter, controller, prompt builder, model selection or product screen.

## States And Service Reconstruction

- **Disconnected:** show permission/configuration fields; send no request.
- **Observe:** authenticate with `GET agents/me`, then read that agent's profile
  using `GET agents/profile?name=...`. Both `recentPosts` and `recentComments`
  must be present. Opening/reopening the authorized workspace and each cycle
  reacquire these facts; no local history is reused.
- **Select:** read `GET home`. Replies to activity on the account's posts take
  priority in workflows permitting replies. Read the selected conversation,
  including nested replies and cursor pages, before selecting an unanswered
  comment. A package observation/page budget ends with an explicit incomplete
  result and no new reply; it never labels a partial thread complete.
- **Prepare:** when appropriate, fetch the latest public GitHub commit through
  HTTP, compare its public source URL with service publication history and ask
  the existing Analyst AI for original factual news, a concrete reply, or no
  action. Only public source/history and owner instructions enter inference.
- **Preview:** show prepared content and the AI provider/model; send nothing.
  The package's `read_only` workflow also sends no content.
- **Preflight:** after inference, reread service publication history or the
  complete conversation. An existing source or owner reply retires the proposed
  action. The host rechecks the owner/package/grant at actual dispatch.
- **Create:** issue one POST for a selected post or reply. The package interprets
  service errors and limits. It does not automatically recreate rejected content.
- **Verify:** if the service returns a verification challenge, ask the same
  inference capability for its answer and submit `POST verify`. Expiry, rejection
  or unavailable inference remain visible failures; no replacement post is sent.
- **Observe receipt:** use an uncredentialed public GET. Match the exact content
  ID, actor, text and post title or reply parent. A pending/failed verification,
  spam/deleted item or absent observation is not publication success. Reply
  visibility may be reread twice after bounded waits. No second creation occurs.
- **Unknown:** on uncertain creation, reread the account's service history once
  and match exact content. Continue from a matching service item; otherwise
  report unknown delivery without retrying that creation in the current action.

Start uses the common scheduler. Full revocation prevents further dispatch and
ends scheduling; it cannot remove content already accepted by Moltbook. Replacement
or removal invalidates in-flight admission, including queued inference. A new
package never inherits the old package digest's grant.

## Stateless Recovery And Limits

Profile history is the service's recent window, not a complete account archive.
Compact samples enter AI while source references and answered-parent identities
are derived from the returned history. Conversation traversal has explicit
package budgets. Larger or incomplete observations end visibly rather than
silently permitting a duplicate reply.

Restart intentionally loses transient drafts, challenges, receipts and unknown
outcomes. It reconstructs from current service history. Moltbook documents no
create idempotency key; if an accepted item remains hidden or absent from its
history after a lost acknowledgement/process exit, this stateless workflow
cannot guarantee exactly-once creation across starts. This is an explicit
changed guarantee, not a host-owned journal or additional approval requirement.
Existing legacy data files are not executed or automatically erased by this code
change. Generic opaque backup/custody preserves existing bytes without replaying
them. Known retired capability metadata remains readable for old-archive recovery
and removal until that archive compatibility is explicitly retired; old named
Moltbook methods have no handler and cannot run.

## Verification And Remaining Acceptance

Package tests exercise fresh history, preview, news, replies, pagination,
post-inference duplicate detection, verification, public receipt matching,
uncertain delivery and failure. The native probe
`flutter/test/fixtures/moltbook_common_api_probe.dart` installs the real ZIP and
runs it through `WasmPluginRuntimeService` and `PluginWorkspaceRuntime` with
synthetic HTTP/AI ports. It verifies restart reconstruction, owner settings,
absence of product-state files, revocation and removal during inference.
There are no live service writes or real AI/Keychain calls in these checks.

Native Keychain interaction and guarded packaged macOS/Android smoke remain
required. A dirty checkout and a canonical runner for different committed source
cannot qualify a release. Live publication is not authorized by these tests.

Protocol reference checked on 2026-11-01: the service's official
[API skill](https://www.moltbook.com/skill.md), including profile recent history,
comment cursor pagination, content creation and verification. No dependency or
runtime-toolchain upgrade is required.
