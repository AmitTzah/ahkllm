# ChatGPT plan backend and Codex image worker

AhkLLM's built-in `chatgpt` provider uses **Sign in with ChatGPT** and OpenAI's public Responses API for normal chat and inline commands. New model IDs use `chatgpt/...` (for example `chatgpt/gpt-5.6-sol`). Historical `codex/...` IDs remain accepted as a non-destructive compatibility alias, so existing chats continue to resolve without a conversation-DB migration.

Codex CLI is no longer the general chat transport. It is an optional, narrowly scoped worker used only when the per-chat **Image Generation** toggle causes the ChatGPT-plan model to call AhkLLM's `ahkllm.generate_image` client tool.

## Setup

1. Open **Settings -> Providers -> ChatGPT plan**.
2. Click **Continue with ChatGPT**.
3. Complete authorization in the system browser.
4. Return to AhkLLM. The provider card shows the selected account and can refresh that account's current model list.
5. Choose a `chatgpt/...` model.

No OpenAI API key is required for this provider. AhkLLM stores the OAuth registration and renewable session in a Windows DPAPI-protected credential file under its data directory; credentials are not written to `settings.json`, API logs, command lines, or AhkLLM portable backups.

The signed-in account must grant the `chatgpt.tokens.use.direct` permission. If identity sign-in succeeds without that permission, AhkLLM retains the account registration but does not perform inference until plan usage is enabled.

After plan usage is enabled, AhkLLM shows a one-time confirmation that eligible requests use the user's ChatGPT plan or available credits. While a `chatgpt/...` model (or a legacy `codex/...` alias, or an assistant based on one) is active, the model card shows **Using ChatGPT plan** with a **Manage usage** link. The provider settings and usage dashboard expose the same usage-management destination.

## Direct Responses transport

Normal ChatGPT-plan requests go directly to:

`POST https://api.openai.com/v1/responses`

AhkLLM sends the selected local conversation path as explicit Responses `input`, lifts system/developer text into `instructions`, sets `store: false` and `stream: true`, and omits `previous_response_id`. AhkLLM therefore remains the sole source of truth for history and branching; there is no second ChatGPT/Codex conversation tree to synchronize.

A streamed request is accepted as successful only after a typed `response.completed` event. A connection that ends with partial text but no terminal completion is treated as a failed/cancelled partial, not as a successful assistant message.

Inline replace/append commands use the same required streamed wire protocol but buffer it inside AhkLLM. Text is pasted into the target application only after `response.completed`; partial streams are never pasted.

## Context behavior

AhkLLM sends the active branch explicitly on every Responses request. It does not silently summarize, trim, compact, or switch to a provider-owned conversation reference.

This removes the old Codex CLI `turn/start` 1,048,576-character stdin limit on accumulated replay. The actual model context window is still enforced by the selected model/service. When the complete AhkLLM branch no longer fits, the request should fail rather than silently altering history.

Attachments remain associated with their original AhkLLM messages. Supported image attachments are converted to Responses `input_image` parts; extracted text from other supported attachments stays in the message context.

## Accounts and model discovery

AhkLLM supports multiple saved ChatGPT registrations. Each registration keeps its issued OAuth `client_id`, verified account identity, and renewable session separately. Switching accounts changes the access token used for model discovery and inference.

**Refresh models** queries `GET https://api.openai.com/v1/models` with the selected account, keeps entries whose `visibility` is `list`, displays `display_name`, and sends the corresponding `slug` as the model ID. The curated fallback catalog uses canonical `chatgpt/...` entries. Legacy `codex/...` references are normalized to the same models at runtime.

Discovery saves the selected account's catalog in `settings.json`, replaces stale ChatGPT model entries, and updates the chat picker and Models settings table. Once discovery succeeds, reloads use that catalog rather than adding bundled fallback models back. A failed refresh keeps the previous catalog; a successful empty catalog removes all ChatGPT model entries. Existing conversation model IDs remain unchanged.

**Models → Fetch Latest Models** also refreshes the ChatGPT catalog when signed in, alongside models.dev metadata for API providers. ChatGPT discovery applies immediately, including to the refresh modal; API-provider selections still use the modal's normal Save flow. Refreshing ChatGPT preserves unrelated unsaved settings edits. If one source fails, results from the other source remain available with a warning.

Refresh tokens are rotating. AhkLLM serializes credential updates with a local mutex and persists the replacement token atomically in the DPAPI-protected store.

## Web Search

When the right-rail **Web Search** toggle is enabled for a ChatGPT-plan chat, AhkLLM exposes the hosted Responses `web_search` tool in that request. It does not route ChatGPT-plan web search through the old Tavily function loop or through Codex CLI.

When Web Search is off, the tool is absent.

Hosted search citations returned as Responses `url_citation` annotations are converted into clickable inline source links before the assistant message is persisted, so citations remain visible after reload and export through the normal chat content path.

## Image Generation

Hosted Responses image generation is not available on the ChatGPT-plan HTTP route used here. AhkLLM therefore exposes one client-side namespaced function when the right-rail **Image Generation** toggle is enabled:

`ahkllm.generate_image({ prompt })`

If the model calls it, AhkLLM:

1. validates that the Image Generation toggle was enabled for the originating request;
2. accepts only the exact `ahkllm.generate_image` function;
3. runs a fresh isolated Codex CLI image worker with the model-supplied self-contained prompt;
4. passes only AhkLLM-managed image attachments that belong to the selected request path;
5. keeps shell, filesystem-inspection, browser, computer-use, MCP, plugins, apps, and unrelated agent surfaces disabled;
6. imports only validated generated PNG output through AhkLLM's existing attachment lifecycle;
7. sends a small `function_call_output` back to the Responses API together with the exact prior `response.output` item sequence; and
8. continues the same stateless AhkLLM turn until `response.completed`.

The Codex worker does **not** receive the AhkLLM conversation tree and does not become a second source of chat state.

### Optional Codex CLI setup for image generation

Image generation requires the official Codex CLI to be installed separately and signed in with ChatGPT. In **Settings -> Providers -> ChatGPT plan**, click **Check Codex CLI** to verify the local worker.

AhkLLM currently requires Codex CLI 0.153.0 or newer for the restricted execution profile. The generated-image discovery path was verified against the 0.154.x behavior already covered by the repository tests. If `codex` is not on `PATH`, set `CODEX_CLI_PATH` before launching AhkLLM.

The worker runs with `--ignore-user-config`, `--ignore-rules`, a read-only sandbox, strict config, no approval prompts, no MCP servers/hooks, and explicit feature disables. Image generation is the only normally disabled feature temporarily enabled for this worker.

Codex CLI 0.154.x does not expose the generated image as a dedicated final JSON item. AhkLLM correlates the public Codex thread ID with the worker's generated-image directory, accepts only PNG files from that correlated location, rejects link/reparse-point paths, validates the PNG signature and size limit, and imports the bytes as normal assistant attachments.

## Cancellation and failures

The chat Stop action terminates the active direct Responses process. If a model is currently inside the Codex image worker, the same cancellation state is shared with the worker so it terminates too.

A cancelled or failed image tool call is not silently converted into a successful text response. Generated attachments are adopted only when the worker succeeds and the final Responses continuation completes.

Authentication, permission, model-availability, rate-limit, and usage-limit failures are surfaced as provider errors. The structured `subscription_sharing_usage_limit_exceeded` error includes a **Manage usage** action that opens ChatGPT Settings -> Usage; inline commands include the same destination in their failure text. AhkLLM does not automatically fall back from ChatGPT-plan usage to an API-key provider.

## Logs and credentials

Prompt/response logging follows AhkLLM's normal API-log settings and locked-chat redaction rules. OAuth access/refresh credentials are excluded from those logs.

The direct HTTP process receives its Authorization header through an inherited stdin curl configuration. The bearer value is not placed in the process command line or in the temporary request/command files.

The DPAPI credential file and stable host-ID file are separate from `settings.json` and are not copied by AhkLLM's portable backup routine. Re-authorize ChatGPT on another machine instead of treating a settings backup as a credential transfer.

## Official references

The implementation follows OpenAI's current **Sign in with ChatGPT -> ChatGPT plan usage for open-source apps** documentation:

- https://developers.openai.com/siwc/token-sharing-open-source/
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery

These interfaces are preview features and can change. AhkLLM intentionally keeps the plan-specific transport isolated behind the stable provider abstraction so chat history remains local and provider-neutral.
