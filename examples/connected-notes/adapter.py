"""Minimal JSON-lines application adapter; note state is owned by its chat branch."""

import json
from pathlib import Path
import sys
import tempfile
import uuid

JOURNALS = Path(tempfile.gettempdir()) / "ahkllm-connected-notes"


def journal_path(turn):
    if not isinstance(turn, str) or len(turn) != 32 or any(char not in "0123456789abcdef" for char in turn):
        raise ValueError("Invalid turn")
    return JOURNALS / (turn + ".json")


def handle(method, params):
    state = params.get("state", {"note": "", "revision": 0, "complete": False})
    if method == "session.describe":
        tools = [{
            "type": "function", "name": "read_note", "description": "Read the current note.",
            "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
        }, {
            "type": "function", "name": "update_note", "description": "Replace the note with agreed content.",
            "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"], "additionalProperties": False},
        }]
        return {
            "label": "Connected Notes", "phase": "complete" if state.get("complete") else "discussion",
            "complete": state.get("complete", False), "tools": tools,
            "actions": [] if state.get("complete") else [{"id": "complete", "label": "Complete this note", "confirm": True}],
        }
    if method == "session.fork":
        return {"state": dict(state)}
    if method == "turn.begin":
        turn = uuid.uuid4().hex
        JOURNALS.mkdir(exist_ok=True)
        journal_path(turn).write_text(json.dumps(state), encoding="utf-8")
        return {"turn": turn}
    if method == "tools.call":
        path = journal_path(params["turn"])
        draft = json.loads(path.read_text(encoding="utf-8"))
        if params["name"] == "read_note":
            return {"result": {"note": draft["note"]}}
        if params["name"] != "update_note":
            raise ValueError("Unknown note tool")
        draft["note"] = params["arguments"]["text"]
        path.write_text(json.dumps(draft), encoding="utf-8")
        return {"result": {"updated": True}}
    if method == "turn.commit":
        draft = json.loads(journal_path(params["turn"]).read_text(encoding="utf-8"))
        return {"state": {**draft, "revision": state.get("revision", 0) + 1}}
    if method in {"turn.accept", "turn.abort"}:
        journal_path(params["turn"]).unlink(missing_ok=True)
        return {"state": state}
    if method == "action.perform" and params["action"] == "complete":
        return {"state": {**state, "complete": True}, "message": "The author confirms the note is complete."}
    if method == "session.release":
        return {"released": True}
    raise ValueError("Unknown application operation")


def main():
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            result = handle(request["method"], request.get("params", {}))
            response = {"jsonrpc": "2.0", "id": request.get("id"), "result": result}
        except Exception as error:
            response = {"jsonrpc": "2.0", "id": request.get("id"), "error": {"code": -32000, "message": str(error)}}
        print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
