# Round 3: Duplicated Logic + Dead Code

## Duplicated Logic (7 patterns)

### 1. `readStreamChunk()` vs `_readStreamChunkFromParams()` — identical SSE parsing
- Both 60-line functions parse SSE chunks identically
- `readStreamChunk()` takes explicit state object (used only by tests)
- `_readStreamChunkFromParams()` reads from global `requestParams` (used by production)
- **Fix**: Extract shared `_parseSSEChunks(state)` pure function that both call

### 2. Max sibling index query — identical SQL at 2 sites
- [`StreamHandler.ahk:446`](chat/StreamHandler.ahk:446) and [`ChatCallbacks_Edit.ahk:40`](chat/ChatCallbacks_Edit.ahk:40)
- Both do: `ChatDB.db.Exec("SELECT MAX(sibling_index) as max_idx FROM messages WHERE sibling_group='" group "';")`
- **Fix**: Add `MessageRepo.GetMaxSiblingIndex(group)` and use it

### 3. `FileExist(x) ? FileDelete(x) : ""` — 3 occurrences
- [`InlineRequestRunner.ahk:105-106`](app/InlineRequestRunner.ahk:105), [`ChatUtils.ahk:37-38`](chat/ChatUtils.ahk:37), [`ChatUtils.ahk:203`](chat/ChatUtils.ahk:203)
- **Fix**: Add `safeDelete(path)` function

### 4. `requestParams["providerName"] := parts.provider` — 2 sites
- [`ChatSettings.ahk:108-109`](chat/ChatSettings.ahk:108) and `ChatSettings.ahk:139-140`
- **Fix**: Extract `_updateProviderFromModel(model)` helper

### 5. ApiLogger duplicate read code — lines 21 and 45
- Both do: `jsongo.Parse(FileOpen(this.logFilePath, "r", "UTF-8-RAW").Read())`
- **Fix**: Extract `_readLogFile()` private method

### 6. Provider API key lookup — 3 times in ProviderResolver
- `EnvGet(p.authEnvVar)` at lines 18, 40, 52
- **Fix**: Extract `_getApiKey(providerObj)` helper

### 7. ProviderResolver returns identical structure 3 times
- `{ providerKey, modelName, apiKey, endpoint, fimEndpoint }` at 3 return sites
- **Fix**: Extract `_buildResult(providerKey, modelName, p)` helper

## Dead Code (1 item)

### 8. `readStreamChunk()` — only used by tests
- Called 3 times in `StreamHandler.test.ahk`
- Production always uses `_readStreamChunkFromParams()`
- **Fix**: After extracting shared `_parseSSEChunks()`, have `readStreamChunk()` delegate to it (keep for tests), remove dead SSE parsing from it

---

## Implementation Plan

### Phase A: Utility extractions (low risk)
1. Add `safeDelete(path)` to `ChatUtils.ahk`
2. Add `MessageRepo.GetMaxSiblingIndex(group)` 
3. Fix ApiLogger dedup
4. Fix ProviderResolver dedup (3 callsites → 1 helper)
5. Fix ChatSettings provider pattern

### Phase B: StreamHandler SSE dedup (medium risk)
6. Extract `_parseSSEChunks(state)` from `_readStreamChunkFromParams()`
7. Have `readStreamChunk()` use `_parseSSEChunks()`
8. Have `_readStreamChunkFromParams()` use `_parseSSEChunks()`

### Phase C: Verify
9. Run all tests (111/111)
10. Launch QA review
