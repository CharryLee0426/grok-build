//! Provider-specific wire adaptation. Authentication is resolved by the caller.
use std::collections::BTreeMap;

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use serde_json::{Value, json};
use xai_grok_sampling_types::{Result, SamplingError, rs};

/// Read a routing claim from the bearer sent on this request. This is not JWT
/// validation; authorization remains the subscription server's responsibility.
pub(crate) fn codex_account_id(bearer: &str) -> Option<String> {
    let payload = bearer.split('.').nth(1)?;
    let claims: Value =
        serde_json::from_slice(&URL_SAFE_NO_PAD.decode(payload.trim_end_matches('=')).ok()?)
            .ok()?;
    claims
        .get("https://api.openai.com/auth")?
        .get("chatgpt_account_id")?
        .as_str()
        .filter(|id| !id.is_empty())
        .map(str::to_owned)
}

pub(crate) fn codex_base_url(base_url: &str) -> String {
    let Ok(mut url) = reqwest::Url::parse(base_url) else {
        return base_url.to_owned();
    };
    let path = url.path().trim_end_matches('/');
    let path = path.strip_suffix("/responses").unwrap_or(path);
    let path = if path.ends_with("/codex") {
        path.to_owned()
    } else {
        format!("{path}/codex")
    };
    url.set_path(&path);
    url.to_string()
}

pub(crate) fn prepare_codex_request(body: &mut Value) {
    let Some(body) = body.as_object_mut() else {
        return;
    };
    body.insert("store".into(), json!(false));
    body.insert("stream".into(), json!(true));
    // Subscription inference does not accept the general Responses API's
    // output limit, stateful response lookup or xAI streaming extension.
    for key in [
        "max_output_tokens",
        "max_tool_calls",
        "temperature",
        "top_p",
        "stream_tool_calls",
        "previous_response_id",
        "conversation",
        "truncation",
        "prompt_cache_retention",
    ] {
        body.remove(key);
    }
    let mut instructions = body
        .remove("instructions")
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_default();
    if let Some(input) = body.get_mut("input").and_then(Value::as_array_mut) {
        // The initial system prompt belongs in `instructions`. Later system
        // reminders retain their position as developer messages.
        while input
            .first()
            .and_then(|item| item.get("role"))
            .and_then(Value::as_str)
            == Some("system")
        {
            let item = input.remove(0);
            let content = item.get("content");
            let text = content
                .and_then(Value::as_str)
                .map(str::to_owned)
                .unwrap_or_else(|| {
                    content
                        .and_then(Value::as_array)
                        .into_iter()
                        .flatten()
                        .filter_map(|part| part.get("text").and_then(Value::as_str))
                        .collect::<Vec<_>>()
                        .join("\n")
                });
            if !instructions.is_empty() && !text.is_empty() {
                instructions.push_str("\n\n");
            }
            instructions.push_str(&text);
        }
        for item in input.iter_mut() {
            if item.get("role").and_then(Value::as_str) == Some("system") {
                item["role"] = json!("developer");
            }
        }
        // Plaintext reasoning synthesized by a different provider has no
        // server-issued identity/signature and cannot be replayed to Codex.
        input.retain(|item| {
            item.get("type").and_then(Value::as_str) != Some("reasoning")
                || item
                    .get("encrypted_content")
                    .and_then(Value::as_str)
                    .is_some_and(|s| !s.is_empty())
        });
    }
    if instructions.is_empty() {
        instructions = "You are a helpful assistant.".into();
    }
    body.insert("instructions".into(), json!(instructions));
    body.entry("parallel_tool_calls").or_insert(json!(true));
    body.entry("tool_choice").or_insert(json!("auto"));
    if let Some(tools) = body.get_mut("tools").and_then(Value::as_array_mut) {
        for tool in tools {
            if tool.get("type").and_then(Value::as_str) == Some("function") {
                // Coding tool schemas have optional fields; do not opt them
                // into Responses' stricter required-field interpretation.
                tool["strict"] = Value::Null;
            }
        }
    }
}

pub(crate) fn prepare_openrouter_request(body: &mut Value, supports_tools: Option<bool>) {
    let Some(body) = body.as_object_mut() else {
        return;
    };
    if let Some(effort) = body.remove("reasoning_effort") {
        body.insert("reasoning".into(), json!({"effort": effort}));
    }
    body.remove("search_parameters");
    if supports_tools == Some(false) {
        for key in ["tools", "tool_choice", "parallel_tool_calls"] {
            body.remove(key);
        }
    }
    if let Some(messages) = body.get_mut("messages").and_then(Value::as_array_mut) {
        for message in messages {
            if let Some(message) = message.as_object_mut() {
                message.remove("model_id");
                if let Some(reasoning) = message.remove("reasoning_content")
                    && message
                        .get("reasoning_details")
                        .and_then(Value::as_array)
                        .is_none_or(Vec::is_empty)
                {
                    message.insert("reasoning".into(), reasoning);
                }
            }
        }
    }
}

/// Codex sometimes ends with `response.done` and omits output on the final
/// response. Reassemble completed items without losing tool calls or reasoning.
#[derive(Default)]
pub(crate) struct CodexEventDecoder {
    output: BTreeMap<u64, Value>,
}

impl CodexEventDecoder {
    pub(crate) fn decode(&mut self, data: &str) -> Result<Option<rs::ResponseStreamEvent>> {
        let mut value: Value = serde_json::from_str(data).map_err(SamplingError::Serialization)?;
        let Some(kind) = value.get("type").and_then(Value::as_str).map(str::to_owned) else {
            return Ok(None);
        };
        if kind == "response.output_item.done" {
            if let (Some(index), Some(item)) = (
                value.get("output_index").and_then(Value::as_u64),
                value.get("item"),
            ) {
                self.output.insert(index, item.clone());
            }
        }
        let terminal = matches!(
            kind.as_str(),
            "response.done" | "response.completed" | "response.incomplete" | "response.failed"
        );
        if kind == "response.done" {
            value["type"] = json!(
                match value.pointer("/response/status").and_then(Value::as_str) {
                    Some("incomplete") => "response.incomplete",
                    Some("failed" | "cancelled") => "response.failed",
                    _ => "response.completed",
                }
            );
        }
        if let Some(object) = value.as_object_mut() {
            object.entry("sequence_number").or_insert(json!(0));
        }
        if let Some(response) = value.get_mut("response").and_then(Value::as_object_mut) {
            response.entry("object").or_insert(json!("response"));
            response.entry("created_at").or_insert(json!(0));
            response.entry("model").or_insert(json!(""));
            response.entry("id").or_insert(json!(""));
            if terminal
                && response
                    .get("output")
                    .and_then(Value::as_array)
                    .is_none_or(Vec::is_empty)
            {
                response.insert(
                    "output".into(),
                    Value::Array(self.output.values().cloned().collect()),
                );
            } else {
                response.entry("output").or_insert(json!([]));
            }
            if let Some(usage) = response.get_mut("usage").and_then(Value::as_object_mut) {
                usage
                    .entry("input_tokens_details")
                    .or_insert(json!({"cached_tokens": 0}));
                usage
                    .entry("output_tokens_details")
                    .or_insert(json!({"reasoning_tokens": 0}));
                let total = usage
                    .get("input_tokens")
                    .and_then(Value::as_u64)
                    .unwrap_or(0)
                    + usage
                        .get("output_tokens")
                        .and_then(Value::as_u64)
                        .unwrap_or(0);
                usage.entry("total_tokens").or_insert(json!(total));
            }
        }
        // New auxiliary events should not break otherwise valid generations.
        if !kind.starts_with("response.") && kind != "error" {
            return Ok(None);
        }
        match super::client::deserialize_response_event(&value.to_string()) {
            Ok(event) => Ok(Some(event)),
            Err(SamplingError::Serialization(error))
                if error
                    .to_string()
                    .contains(&format!("unknown variant `{kind}`"))
                    && !terminal =>
            {
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_endpoint_accepts_base_codex_and_full_endpoint_with_query() {
        for input in [
            "https://chatgpt.com/backend-api",
            "https://chatgpt.com/backend-api/codex/",
            "https://chatgpt.com/backend-api/codex/responses",
        ] {
            assert_eq!(
                codex_base_url(input),
                "https://chatgpt.com/backend-api/codex"
            );
        }
        assert_eq!(
            codex_base_url("https://example.test/backend-api?tenant=one"),
            "https://example.test/backend-api/codex?tenant=one"
        );
    }

    #[test]
    fn codex_preserves_reminder_position_and_native_encrypted_reasoning() {
        let mut body = json!({"input":[
            {"role":"system","content":"Initial rules"},
            {"role":"user","content":"Task"},
            {"role":"system","content":"Later reminder"},
            {"type":"reasoning","id":"","summary":[]},
            {"type":"reasoning","id":"rs_123","encrypted_content":"opaque","summary":[]}
        ],"store":true,"max_output_tokens":100,"top_p":0.5});
        prepare_codex_request(&mut body);
        assert_eq!(body.get("instructions"), Some(&json!("Initial rules")));
        assert_eq!(body.pointer("/input/1/role"), Some(&json!("developer")));
        assert_eq!(
            body.pointer("/input/2/encrypted_content"),
            Some(&json!("opaque"))
        );
        assert_eq!(body.get("input").unwrap().as_array().unwrap().len(), 3);
        assert!(body.get("max_output_tokens").is_none());
    }

    #[test]
    fn openrouter_omits_tools_for_models_without_tool_support() {
        let mut body = json!({"messages":[],"tools":[{"type":"function"}],"tool_choice":"auto","parallel_tool_calls":true});
        prepare_openrouter_request(&mut body, Some(false));
        assert!(body.get("tools").is_none());
        assert!(body.get("tool_choice").is_none());
        assert!(body.get("parallel_tool_calls").is_none());
    }

    #[test]
    fn codex_incomplete_terminal_remains_incomplete() {
        let mut decoder = CodexEventDecoder::default();
        let event = decoder.decode(&json!({"type":"response.done","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}).to_string()).unwrap().unwrap();
        assert!(matches!(
            event,
            rs::ResponseStreamEvent::ResponseIncomplete(_)
        ));
    }
}
