# AI completion for this config — options & decision doc

> Status: **v1 — decision made, ready to implement in stages.**
> Goal: pipe AI completion suggestions into blink.cmp from multiple providers —
> codex, claude, pi, deepseek, ollama/openrouter, … — with enough context that
> suggestions are actually sensible.
>
> Method note: websearch was down during research; every external claim below was
> verified by fetching the primary docs directly (DeepSeek API docs, pi-mono repo
> docs, minuet-ai.nvim README, plus the installed blink.cmp v1.10.2 source).

## 0. What we measured on this machine (ground truth)

| Path | Startup | One-shot end-to-end¹ | Notes |
|---|---|---|---|
| `codex exec` (0.84.4) | ~60 ms | **5.4 s** | ChatGPT login. Injects ~7.2k tokens of its own prompt per call. `--json`, `-o FILE`, `--ephemeral`, `-s read-only` available. |
| `claude -p` | ~2.2 s | — | **Auth broken** (401 token revoked). **Skipped for now** per decision. `-p --output-format stream-json --include-partial-messages` exists for later. |
| `pi -p --mode json` | ~0.2 s | **5.8 s** | Clean NDJSON event stream with `text_delta` streaming; only ~1.5k tokens of built-in prompt overhead. Currently bridged to `openai-codex` / gpt-5.5 via the ChatGPT login. |
| ollama | daemon running | probe inconclusive (27B model, cold load > 2 min) | M5 Max / 128 GB — a 1.5–7B coder FIM model is the right size. None pulled yet. |
| API keys in env | — | — | None. Provider access today = harness subscriptions only. |

¹ Trivial prompt ("reply with the word ok"), no tools, no session.

**The decisive fact:** harness round-trips are ~5–6 s. Fine when *you* ask for a
suggestion; hopeless for keystroke-triggered inline completion. Hence a **two-tier
design** — this is decision D1, and everything else follows from it:

- **Fast tier** (automatic ghost text while typing): API/local models — ollama,
  OpenRouter, DeepSeek FIM. Sub-second-ish.
- **Deep tier** (on-demand keymap): the harnesses — pi, codex, (claude later). You
  trigger it, wait seconds, accept/dismiss the result.

## 1. Verified facts about the building blocks

### blink.cmp v1.10.2 (installed) — the integration surface
- Custom source contract (`lua/blink/cmp/sources/lib/types.lua`):
  `get_completions(self, context, callback)` may **return a cancel function** — blink
  cancels stale requests itself when the cursor moves. `execute(...)` runs **on accept**
  (copilot-style prefetch hook). `resolve`, `should_show_items`, `min_keyword_length`,
  `score_offset`, `transform_items` all per-provider and function-capable.
- `sources.per_filetype` (with `inherit_defaults = true`) — enable AI per-filetype
  without touching the upstream `default` list.
- Ghost text is first-class: `completion.ghost_text = { enabled = true,
  show_with_menu = false }`; keymaps accept `on_ghost_text = true` for cycling while
  only ghost text is visible.
- Manual deep-tier trigger: `cmp.show({ providers = { 'ai-harness' } })`.

### pi (0.84.4) — the universal harness adapter (docs: badlogic/pi-mono, `packages/coding-agent/docs/`)
- **Providers** (`docs/providers.md`): subscriptions (OpenAI Codex, Claude Pro/Max,
  GitHub Copilot, xAI, OpenRouter) + API keys for **DeepSeek**, OpenRouter, Mistral,
  Groq, Together, HF, … + **custom OpenAI-compatible providers via `baseUrl`**
  (`docs/custom-provider.md`) — i.e. ollama/llama.cpp/LM Studio.
- **`--mode rpc`** (`docs/rpc.md`): headless JSONL protocol over stdin/stdout —
  `{"id":"req-1","type":"prompt","message":"..."}`, streaming `message_update` events,
  abort, queueing, session control. A persistent pi process can front *every* provider
  with no per-call cold start.
- `--no-tools`, `--thinking off`, `-p --mode json` for one-shot; measured 5.8 s today.

### DeepSeek API (docs: api-docs.deepseek.com, 2026)
- Models now: `deepseek-v4-flash` / `deepseek-v4-pro` (also an Anthropic-compatible
  base_url `https://api.deepseek.com/anthropic`).
- **FIM Completion (Beta) is alive** (2026): `base_url = https://api.deepseek.com/beta`,
  `completions.create(model, prompt, suffix, max_tokens)`, max 4k output tokens.
  Doc: `https://api-docs.deepseek.com/guides/fim_completion`.
- Also "Chat Prefix Completion (Beta)" — continuation of a supplied prefix via chat.

### minuet-ai.nvim (README, 2026) — the fast tier, off the shelf
- Frontends: `virtual-text`, `nvim-cmp`, **`blink-cmp` (`module = 'minuet.blink'` +
  `require('minuet').make_blink_map()`)**, built-in, in-process LSP.
- Providers: `openai`, `claude` (default haiku-4.5), `codestral`, `gemini`,
  **`openai_compatible`** (docs literally show OpenRouter → `deepseek/deepseek-v4-flash`)
  and **`openai_fim_compatible`** (docs show **DeepSeek FIM `/beta`**, **Ollama
  qwen2.5-coder:7b**, **llama.cpp 1.5b with custom `<|fim_prefix|>` templates**).
- Knobs: `debounce`, `n_completions`, `context_window`, `stream`, `request_timeout`,
  `add_single_line_entry`, system/few-shot/chat templates, config **presets**.
- Runtime switching: `:Minuet change_provider`, `:Minuet change_model`, `:Minuet change_preset`.

## 2. Integration surface — options considered

| Option | Verdict |
|---|---|
| **A. blink.cmp custom source + blink ghost text** | **Chosen** — for the deep tier (and it's what minuet does for the fast tier). Cancel-on-stale is free (`return cancel_fn`), `execute` gives prefetch-on-accept, `cmp.show({providers=…})` gives manual trigger. |
| B. Standalone ghost-text engine (copilot.lua style) | Rejected — rebuilds what blink does; two ghost-text engines can fight. |
| C. Fake LSP server shim | Rejected — an extra daemon + protocol for a personal config; context must be shipped over the wire anyway. Revisit only if we want editor-agnostic tooling. |

## 3. Provider adapter landscape — where each path landed

| Adapter | Tier | Verdict |
|---|---|---|
| **minuet-ai.nvim** | fast | **Adopt.** Covers ollama + OpenRouter (your stated preference) + DeepSeek FIM + claude/codestral APIs, blink integration, debounce/stream/switching/presets. Building this ourselves would be re-deriving a maintained plugin. |
| **pi RPC (persistent) / `pi -p --mode json` (one-shot)** | deep | **Primary deep adapter.** One protocol, broadest provider reach (codex models already work via your ChatGPT login), leanest prompt overhead (1.5k vs codex's 7.2k), native DeepSeek/OpenRouter/ollama coverage if we ever want harness-style calls to those. |
| `codex exec --json` | deep | Secondary adapter; works today, but heaviest per call (7.2k-token prompt, 5.4 s). |
| `claude -p` | deep | Adapter trivial; **blocked on your CLI auth (401)**. Skipped for now. |
| Direct HTTP from Lua (curl) | fast | Only needed if we reject minuet; not needed for v1. |

## 4. Decision log

- **D1 — two tiers** (automatic fast + on-demand deep). Basis: measured ~5–6 s harness
  latency (§0). *Made.*
- **D2 — blink source + blink ghost text as the only UI surface** (§2A). *Made.*
- **D3 — minuet-ai.nvim for the fast tier** (§3). *Made.* Covers `ollama`/`openrouter`
  routing exactly as requested, plus DeepSeek FIM if you later want the best hosted
  quality (needs a cheap API key — DeepSeek FIM is native there; OpenRouter has no FIM
  endpoint, so it goes through `openai_compatible` chat-style with minuet's templates).
- **D4 — pi is the deep-tier adapter**, codex-exec second, claude deferred until login
  is fixed. *Made.* Start with one-shot `pi -p --mode json`; upgrade to persistent
  `pi --mode rpc` if one-shot overhead annoys.
- **D5 — context builder**: minuet owns fast-tier context (its `context_window`,
  templates, `add_single_line_entry`). A small custom context builder (§6) is shared
  with the deep tier. *Made, sized in Stage 2.*
- **D6 — privacy/keys**: no API keys today; fast tier starts on **ollama local**
  (private) with `openai_compatible`/DeepSeek entries ready to fill in. *Made, per
  your "configurable via ollama / openrouter" answer.*

## 5. Target architecture

```
blink.cmp (only completion UI; ghost_text enabled)
├── sources: lsp, path, snippets            (unchanged, upstream)
├── source:  minuet.blink                    (fast tier — automatic, ollama/openrouter/deepseek)
└── source:  custom.ai.source 'ai-harness'   (deep tier — manual trigger)
             └── providers: pi (json → rpc later), codex exec, [claude -p later]
             └── context builder (L2 project-aware) — shared lua module
```

New files (all in the merge-free zone; no upstream edits — blink opts are extended by
re-declaring `sources.default` with the two extra ids):

- `lua/custom/plugins/ai.lua` — lazy spec: minuet-ai + blink opts extension + keymaps +
  `:Minuet`/`<leader>a*` wiring.
- `lua/custom/ai/source.lua` — the `ai-harness` blink source (~100 lines; contract
  verified in §1).
- `lua/custom/ai/harness/pi.lua` / `codex.lua` — spawn one-shot JSON calls
  (`vim.system`), parse NDJSON, extract text.
- `lua/custom/ai/context.lua` — L2 context builder (§6) + secret redaction.

## 6. Context — what makes suggestions "sensible"

Shared builder, three depths; providers declare what they accept:

- **L0 inline** (minuet's job): path + ft + prefix (~16k chars window) + suffix, FIM-shaped.
- **L1 syntax-aware** (minuet templates + small additions): treesitter outline of the
  enclosing scope, imports block, diagnostics on the cursor line.
- **L2 project-aware** (deep tier, ours): file symbol outline, `git diff --stat` +
  last commit subject, capped `rg --files` listing, contents of files named by imports
  under a char budget — all redacted: `(api[_-]?key|token|secret|password)\s*[:=]…`
  lines are masked before anything leaves the machine.
- Per-provider instruction block: "continue at the cursor; code only; no fences/prose";
  stop sequences; harnesses run with `--no-tools`/read-only so they *can't* act.

## 7. UX

- Fast tier: ghost text as you type (minuet defaults, tuned `debounce`), `<A-y>` accept
  via `make_blink_map()`, cycle with `<A-]>`/`<A-[>`.
- Deep tier: `<leader>aa` → `cmp.show({ providers = { 'ai-harness' } })` on the current
  function/selection; suggestion lands as ghost text; auto-dismiss on cursor move;
  `execute` prefetch on accept for follow-up lines.
- `<leader>ap` — snacks.picker over providers (minuet providers + harness pair);
  `:Minuet change_preset` for project-shaped presets. lualine segment: active provider
  + last latency (from the source's timing).

## 8. Staged implementation plan

1. **Stage 1 — fast tier, zero custom code:** install minuet-ai.nvim in
   `lua/custom/plugins/ai.lua`, `openai_fim_compatible` → ollama (`qwen2.5-coder:7b`
   or `1.5b` — needs one `ollama pull`), blink setup per README, tune `debounce`
   (start 300–400 ms). *Exit: ghost text from a local model.*
2. **Stage 2 — deep tier:** `custom.ai.source` + `pi.lua` (one-shot) + L2 context;
   keymap `<leader>aa`. *Exit: manual pi-sourced suggestions with real context.*
3. **Stage 3 — routing + switching:** add `openai_compatible` → OpenRouter entry
   (key in env/auth), presets per project (`local-only`, `cloud`, `deep=pi`),
   provider picker, lualine status.
4. **Stage 4 — hardening:** `pi --mode rpc` persistent adapter (kill one-shot startup +
   enable provider switching mid-session), codex-exec adapter, telemetry log
   (latency/tokens per call), optional claude adapter once you re-login.
5. **Ongoing:** context tuning driven by the telemetry log.

## 9. Open questions (non-blocking)

- Which local coder model — `qwen2.5-coder:1.5b` (fastest, weakest) vs `7b`
  (better, still sub-second on M5 Max)? Decide by feel in Stage 1.
- Do you want a DeepSeek key eventually for the best hosted fast tier? (FIM-native,
  ~$0.27/M input; also usable from pi/minuet alike.) Optional.
- Accept-key choice (`<A-y>` from minuet vs a `<Tab>`-ish binding) — settle by feel.
