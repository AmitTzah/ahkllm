# Connect applications to AhkLLM

External applications can use AhkLLM's existing chat window, model picker, persistence,
message editing, retries, and conversation trees. The application supplies context,
tools, author actions, and opaque checkpoints. AhkLLM has no knowledge of the
application's business rules and makes the model requests itself.

No extra always-running service is required. AhkLLM launches the registered program
on demand, writes a UTF-8 JSON-RPC request to its standard input, reads its standard
output, and closes the process after the exchange. Programs may process multiple
newline-delimited requests, but must support EOF after a single request. Diagnostics
belong on stderr; stdout must contain only the matching JSON-RPC response.

## Register once, then open sessions

Open **Settings -> Applications** to see registered connections and their chat counts.
Use **Add application** to configure a name, stable connection ID, program, arguments
(one per line), working folder, and timeout. **Save connection** persists immediately;
it is separate from the general Settings Save button. **Edit** updates a connection
without changing its ID. **Disconnect** removes its registration and keeps its chats.
Running tasks must finish before their connection can be edited or disconnected.
Applications registered through the launcher appear in this same tab automatically.


Create a connection profile:

```json
{
  "id": "connected-notes",
  "name": "Connected Notes",
  "command": ["python", "PATH_TO_ADAPTER/adapter.py"],
  "working_directory": "PATH_TO_ADAPTER",
  "timeout_seconds": 60
}
```

`command` is an executable and an argument array, never a shell command. Register
only programs you trust: they execute with your normal user permissions. Registration
shows the program and asks for confirmation once, or again if the profile changes.
Imported session packages reference a registered ID and cannot install or execute a
different program themselves.

From your application, launch AutoHotkey v2 with:

```text
AutoHotkey64.exe app/ExternalSessionLauncher.ahk --register connection.json --open session.json
```

Use absolute paths when invoking it outside the AhkLLM directory. The launcher starts
AhkLLM when necessary or contacts its existing instance, brings up the window, and
opens the chat. The optional `--target-window HWND` targets an existing AhkLLM instance
explicitly. This is also used by isolated GUI tests.

A session package is:

```json
{
  "protocol": "ahkllm.external-applications",
  "version": 1,
  "request_id": "a-unique-id-for-this-open-request",
  "application_id": "connected-notes",
  "title": "Plan a research note",
  "instructions": "Collaborate on the note using the supplied tools.",
  "message": "Help me organize this note.",
  "initial_input": "Help me organize this note.\n\nComplete prepared context goes here.",
  "state": {"note": "My original note", "revision": 0, "complete": false}
}
```

`message` is displayed in the chat; `initial_input` is the full initial model input.
The same `request_id` reopens the same retained chat instead of creating duplicates.
New sessions use new IDs. Context is losslessly segmented at UTF-8 text boundaries.
Connected chats preserve the supplied title even when automatic title generation is
enabled. Users can still rename them manually. Hiding the chat window or switching
chats keeps connected requests and tool calls running in the background. The normal
completion sound setting applies. Active turns show **Working…**; recovery actions
are reserved for pending operations with no running request in this instance.
The imported task waits for **Run prepared request**, so the user can select a model
and reasoning level first.
New imported chats start with the model or assistant configured under **New Chats
Start With**, including the configured font size. Application instructions remain
the chat's explicit system prompt. Reopening a retained chat keeps its saved selection.

## Protocol version 1

Each request has this form:

```json
{"jsonrpc":"2.0","id":"request-id","method":"session.describe","params":{"state":{"revision":0}}}
```

Respond with `{"jsonrpc":"2.0","id":"request-id","result":{...}}`, or an `error`
object containing `code` and `message`. The `state` value is opaque to AhkLLM; the
application must treat a checkpoint as immutable. A changed state produces a new
checkpoint rather than modifying a checkpoint referenced by another branch.

| Method | Additional parameters | Result |
|---|---|---|
| `session.describe` | — | `label`, `phase`, `complete`, optional `can_run`, `tools`, `actions` |
| `session.fork` | — | `state` for an independent continuation at the selected checkpoint |
| `turn.begin` | — | `turn`, an opaque operation identifier; optional updated `state`, `message`, `tools`, `phase` |
| `tools.call` | `turn`, `name`, `arguments` | `result`, the tool's structured result |
| `turn.commit` | `turn` | Newly validated `state`; retain recovery information until acceptance |
| `turn.accept` | `turn`, with the committed `state` | Acknowledge that the chat/checkpoint is durably saved |
| `turn.abort` | `turn`, with the original `state` | Restore or safely reconcile interrupted changes |
| `action.perform` | `action` | New `state` and a `message` containing the next full model input |
| `session.release` | — | `released`; idempotently release an unreferenced checkpoint |

Tools use flat Responses function definitions: `type`, `name`, `description`,
`parameters`, and optional `strict`. AhkLLM adapts them for ChatGPT-plan Responses
or OpenAI-compatible HTTP function-calling providers. Other transports fail visibly
instead of silently dropping tools. Ordinary provider capability limits still apply.
Existing attachments are included alongside the application's prepared context.

Actions are arrays of `{ "id": "approve", "label": "Approve proposed changes",
"confirm": true }`. They are user controls, never model-callable functions. The
application verifies which actions are allowed. An action that leaves the task open
supplies the next user input and starts a model turn; completion does not. Actions
are tied to the displayed thread and leaf to reject stale clicks after navigation.
Optional `description` text is shown beside the action, and `confirmation_message`
replaces the generic confirmation question. Use these to explain the consequences
before the user acts. Controls appear in a collapsible task panel above the composer.

Use `can_run:false` when a checkpoint requires recovery or author reconciliation
before another model request. AhkLLM displays the supplied actions and errors.
An optional `notice` explains the reason. Blocked checkpoints open the task controls
automatically, including when regeneration selects an older checkpoint. No provider
request starts until the user resolves the application's required action.

## Persistence, branches, and recovery

AhkLLM saves the complete wire/tool history separately from displayed prose. Editing
or retrying creates an alternative branch; connected-message edits use branching
even when the ordinary overwrite option is selected. Tool records remain immutable.
Editing an action message starts from its preceding checkpoint and drops that action's
supplied context, so edited text cannot impersonate an approval. Forked chats inherit
the registered connection and call `session.fork` at the selected checkpoint.

Checkpoint state belongs to the selected history. Switching branches restores that
state; it does not automatically undo files modified by the application. Applications
that edit files should detect changed hashes and reconcile current context before a turn.
A `turn.begin` result may supply a new immutable `state`, a context `message`, updated
`tools`, and `phase`. AhkLLM uses them for this turn without another user action.
The message is appended to the provider input and durably replayed with the completed
response, so later turns retain the reconciled context. Omitted fields preserve the
existing state and tools. Applications must revoke outdated editing approvals when
reconciling; automatic context updates must not grant new permissions.
They should journal edits before changing files and validate before `turn.commit`.
If chat persistence fails, AhkLLM aborts the turn. If acceptance is interrupted after
chat persistence, `session.describe` should reconcile the committed checkpoint.

Deleting a connected message with descendants is rejected because reparenting would
invalidate its later checkpoints. Fork/edit a branch or delete the entire chat instead.
Permanent deletion cascades integration records and queues unreferenced checkpoints
for release. Shared checkpoints remain until no retained branch references them.
Unavailable applications leave cleanup queued for a later reconnect. Disconnecting
the application removes its registration while keeping historical chats readable.
Backups include the generic registration file and the integration tables in SQLite;
application-owned external files need that application's own backup policy.

The fixed tables are `application_sessions`, `application_nodes`, and
`application_release_queue`. Applications never create their own tables in AhkLLM.

## Example and tests

`examples/connected-notes/adapter.py` is a minimal application-neutral adapter. Replace
the placeholders above with its location, register it, and open the example package.
It stores the note in immutable checkpoint objects and uses temporary journals only
for active turns. It does not require a web server or AhkLLM-specific Python package.

Run `npm run test:fast` and `npm run test:e2e` before changing the protocol or lifecycle.
The GUI regression scenarios exercise the public launcher and real subprocess tools
with isolated profiles and mock model endpoints; they never use real account traffic.
