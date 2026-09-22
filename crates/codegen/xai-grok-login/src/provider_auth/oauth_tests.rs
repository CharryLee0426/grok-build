use super::*;
use wiremock::matchers::{body_json, body_string_contains, method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

#[test]
fn oauth_urls_include_pkce_and_protected_callback() {
    for provider in [ModelProvider::OpenRouter, ModelProvider::OpenAiCodex] {
        let redirect = Url::parse("http://localhost:1455/auth/callback").unwrap();
        let flow = AuthorizationFlow::new(provider, redirect).unwrap();
        let params: std::collections::HashMap<_, _> = flow.authorize_url.query_pairs().collect();
        assert_eq!(
            params.get("code_challenge_method").map(|s| s.as_ref()),
            Some("S256")
        );
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(flow.verifier.as_bytes()));
        assert_eq!(
            params.get("code_challenge").map(|s| s.as_ref()),
            Some(challenge.as_str())
        );
        assert!(flow.verifier.len() >= 43);
        if provider == ModelProvider::OpenRouter {
            let callback = Url::parse(params.get("callback_url").unwrap()).unwrap();
            assert!(
                callback
                    .query_pairs()
                    .any(|(key, value)| key == "state" && value == flow.state)
            );
        } else {
            assert_eq!(
                params.get("state").map(|s| s.as_ref()),
                Some(flow.state.as_str())
            );
            assert_eq!(
                params.get("client_id").map(|s| s.as_ref()),
                Some(CODEX_CLIENT_ID)
            );
        }
    }
}

#[test]
fn callback_rejects_forgery_missing_and_duplicate_parameters() {
    let expected = Url::parse("http://localhost:1455/auth/callback").unwrap();
    for input in [
        "http://localhost:1455/auth/callback?code=secret",
        "http://localhost:1455/auth/callback?code=secret&state=wrong",
        "http://localhost:1455/auth/callback?code=secret&state=expected&state=expected",
        "http://localhost:1455/auth/callback?code=one&code=two&state=expected",
        "http://localhost:1455/other?code=secret&state=expected",
        "http://attacker.test:1455/auth/callback?code=secret&state=expected",
        "http://localhost:1456/auth/callback?code=secret&state=expected",
        "http://localhost:1455/auth/callback?state=expected",
        "http://localhost:1455/auth/callback?state=expected&code=",
        "http://localhost:1455/auth/callback?state=expected&code=secret#fragment",
    ] {
        let error =
            validate_callback(&expected, "expected", &Url::parse(input).unwrap()).unwrap_err();
        assert!(!error.to_string().contains("secret"));
    }
    let valid =
        Url::parse("http://localhost:1455/auth/callback?state=expected&code=valid-code").unwrap();
    assert_eq!(
        validate_callback(&expected, "expected", &valid).unwrap(),
        "valid-code"
    );
}

#[tokio::test]
async fn invalid_callback_does_not_consume_login() {
    let (tx, mut rx) = oneshot::channel();
    let state = CallbackState {
        redirect_url: Url::parse("http://localhost:1455/auth/callback").unwrap(),
        expected_state: "expected".to_owned(),
        result: Arc::new(Mutex::new(Some(tx))),
    };
    let wrong = callback(
        State(state.clone()),
        "/auth/callback?state=wrong&code=secret".parse().unwrap(),
    )
    .await;
    assert_eq!(wrong.status(), StatusCode::BAD_REQUEST);
    assert!(matches!(
        rx.try_recv(),
        Err(oneshot::error::TryRecvError::Empty)
    ));
    let correct = callback(
        State(state.clone()),
        "/auth/callback?state=expected&code=valid-code"
            .parse()
            .unwrap(),
    )
    .await;
    assert_eq!(correct.status(), StatusCode::OK);
    assert_eq!(rx.await.unwrap().unwrap(), "valid-code");
    let reused = callback(
        State(state),
        "/auth/callback?state=expected&code=valid-code"
            .parse()
            .unwrap(),
    )
    .await;
    assert_eq!(reused.status(), StatusCode::CONFLICT);
}

#[tokio::test]
async fn denial_requires_state_and_stops_login_without_echoing_details() {
    let (tx, rx) = oneshot::channel();
    let state = CallbackState {
        redirect_url: Url::parse("http://localhost:1455/auth/callback").unwrap(),
        expected_state: "expected".to_owned(),
        result: Arc::new(Mutex::new(Some(tx))),
    };
    let response = callback(
        State(state),
        "/auth/callback?state=expected&error=denied&error_description=secret"
            .parse()
            .unwrap(),
    )
    .await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let error = rx.await.unwrap().unwrap_err();
    assert!(!error.to_string().contains("secret"));
}

#[tokio::test]
async fn openrouter_exchange_uses_pkce_and_returns_api_key() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(body_json(serde_json::json!({
            "code": "code", "code_verifier": "verifier", "code_challenge_method": "S256"
        })))
        .respond_with(
            ResponseTemplate::new(200).set_body_json(serde_json::json!({"key": "openrouter-key"})),
        )
        .expect(1)
        .mount(&server)
        .await;
    let credential = exchange_openrouter("code", "verifier", &server.uri())
        .await
        .unwrap();
    assert_eq!(credential.access_token(), "openrouter-key");
    assert!(credential.expires_at().is_none());
}

#[tokio::test]
async fn codex_exchange_uses_authorization_code_grant() {
    let server = MockServer::start().await;
    let token = format!(
        "e30.{}.signature",
        URL_SAFE_NO_PAD
            .encode(r#"{"https://api.openai.com/auth":{"chatgpt_account_id":"account"}}"#)
    );
    Mock::given(method("POST"))
        .and(body_string_contains("grant_type=authorization_code"))
        .and(body_string_contains(
            "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback",
        ))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "access_token": token, "refresh_token": "refresh", "expires_in": 3600
        })))
        .expect(1)
        .mount(&server)
        .await;
    let flow = AuthorizationFlow::new(
        ModelProvider::OpenAiCodex,
        Url::parse(CODEX_REDIRECT_URI).unwrap(),
    )
    .unwrap();
    let credential = exchange_codex("code", &flow, &server.uri()).await.unwrap();
    assert_eq!(credential.account_id(), Some("account"));
    assert_eq!(credential.access_token(), token);
}

#[tokio::test]
async fn token_exchange_does_not_follow_redirects_with_secrets() {
    let server = MockServer::start().await;
    Mock::given(path("/redirect"))
        .respond_with(
            ResponseTemplate::new(307)
                .insert_header("location", format!("{}/capture", server.uri())),
        )
        .expect(1)
        .mount(&server)
        .await;
    Mock::given(path("/capture"))
        .respond_with(
            ResponseTemplate::new(200).set_body_json(serde_json::json!({"key": "unexpected-key"})),
        )
        .expect(0)
        .mount(&server)
        .await;
    let error = exchange_openrouter(
        "secret-code",
        "secret-verifier",
        &format!("{}/redirect", server.uri()),
    )
    .await
    .unwrap_err();
    assert!(!format!("{error:#}").contains("secret"));
}
