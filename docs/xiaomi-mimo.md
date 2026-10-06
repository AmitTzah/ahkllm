# Xiaomi MiMo

In Settings → Providers, choose **Add Xiaomi MiMo** if it is not already listed.
Save, then open Settings → Models → **Fetch Latest Models** to load its catalog.
New installations include the MiMo 2.6 Flash, Pro, and Pro Ultraspeed entries.
Removing a provider remains respected; the preset does not silently replace saved providers or credentials.

The default endpoint is `https://api.xiaomimimo.com/v1/chat/completions`.
Set `MIMO_API_KEY` in your Windows environment, then restart AhkLLM so it inherits the value.
Existing environment/direct-key settings work; no key is embedded in the code.

The default uses pay-as-you-go API billing, not your ChatGPT subscription.
Xiaomi Token Plan uses its own key and dedicated endpoint; use the exact endpoint supplied in your Xiaomi console, with `/chat/completions` appended to its OpenAI-compatible base URL.
Displayed model prices are pay-as-you-go estimates and do not represent Token Plan quota consumption.

Choose `xiaomi/mimo-v2.6-pro` or another configured MiMo model in the connected chat.
Model Default leaves Xiaomi's default thinking behavior intact. High enables thinking; None disables it. MiMo exposes one thinking intensity, not separate low/medium/high intensities.

AhkLLM records the exact returned `reasoning_content` together with each assistant tool exchange and replays it on later native HTTP requests, including persisted branches and forks. UI tool-status summaries are not used as provider reasoning.
When switching to a Responses model, the HTTP-only reasoning field is omitted from that wire request without modifying stored history.
The generic optional text-protocol setting remains available, but Xiaomi does not require it.

Native tool streams are correlated by call ID as well as their current wire index. A new call ID reusing index 0 cannot overwrite a previous call or inherit its argument fragments.

MiMo has returned an incomplete native call when a nullable parameter was emitted as literal `null`, while leaking the complete XML-like call into ordinary content. The client workaround stays in native mode: nullable object properties are made optional, `null` is removed from their advertised wire types, and the model is told to omit them when no value applies. Omitted required nullable properties are restored to JSON null before validation against the original application schema and before RPC execution. Nested object properties within arrays receive the same treatment; non-nullable required fields and application write permissions do not change. The projected function schema uses `strict:false` because its nullable parameters are intentionally optional; local validation still uses the original schema.

Sources: [API reference](https://mimo.mi.com/docs/en-US/api/chat/openai-api), [thinking](https://mimo.mi.com/docs/en-US/quick-start/usage-guide/text-generation/deep-thinking), [authentication and plan endpoints](https://mimo.mi.com/docs/en-US/quick-start/summary/first-api-call), [pricing](https://mimo.mi.com/docs/en-US/price/pay-as-you-go).
