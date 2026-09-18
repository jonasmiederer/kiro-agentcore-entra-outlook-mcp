# Phase 2 — Kiro client config & verification (design doc §6 + §8)

After `scripts/deploy.sh` succeeds, grab the `GatewayUrl` output.

## Kiro `mcp.json` — working config (mcp-remote proxy)

The native Kiro remote-MCP OAuth client does **not** work against an Entra-fronted
AgentCore Gateway (see "Why native doesn't work" below). The working path runs the
Gateway through the `mcp-remote` proxy. Put this in `.kiro/settings/mcp.json`
(project scope) or `~/.kiro/settings/mcp.json` (global):

```json
{
  "mcpServers": {
    "outlook": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote@latest",
        "https://<gateway-id>.gateway.bedrock-agentcore.<region>.amazonaws.com/mcp",
        "7778",
        "--disable-resource-parameter",
        "--static-oauth-client-info", "{\"client_id\":\"<KiroClientAppId>\"}",
        "--static-oauth-client-metadata", "{\"scope\":\"openid profile offline_access api://<ApiAppClientId>/access_as_user\"}"
      ]
    }
  }
}
```

- **`7778` (positional, right after the URL)** pins the OAuth callback port.
- `--disable-resource-parameter` omits the RFC 8707 `resource` param → fixes
  `AADSTS9010010` (mcp-remote's README names this exact error).
- `--static-oauth-client-info` pins the Entra client ID (no DCR on Entra).
- `--static-oauth-client-metadata` pins the requested scope (incl.
  `api://<ApiAppClientId>/access_as_user`, which makes Entra mint a token whose
  `aud` = the API app — without it the Gateway can't validate the token).
- Requires Node ≥ 20. First run opens the browser for Entra sign-in; the token caches
  under `~/.mcp-auth`. If a prior attempt failed, `rm -rf ~/.mcp-auth` before retry.


### Why the native Kiro flow does NOT work with Entra

Do **not** use the `"url" + "oauth"` native block; it fails at sign-in. This is not a
defect in Kiro or AgentCore Gateway — both follow the MCP/OAuth 2.0 specs. It's where
Entra diverges from them:

- **Resource indicators (RFC 8707):** Kiro correctly sends the `resource` parameter
  (the Gateway URL); Entra rejects any value that isn't a registered `api://<app-id>`
  audience → `AADSTS9010010 (invalid_target)`.
- **No dynamic client registration (RFC 7591)** and a hard requirement that the
  `api://.../access_as_user` scope be present on `/authorize`, else
  `AADSTS900144 (missing scope)`.

The native client can't suppress or inject these without breaking spec compliance.
The `mcp-remote` proxy bridges the Entra quirks (pins the client ID and scope, omits
`resource`), which is why the proxy path works where native cannot.

## Common failure → cause

| Symptom | Cause |
|---|---|
| Gateway rejects token, `iss` mismatch | API app manifest missing `requestedAccessTokenVersion:2` |
| Gateway 401 on valid user | `aud` is the `api://` URI not the GUID, or `azp` != Kiro client |
| Graph 403 during OBO | admin consent not granted on delegated Graph scopes, or `GraphScopes` ⊄ consented scopes |
| Kiro can't discover auth server | Entra serves OIDC discovery only → use `mcp-remote --static-oauth-client-info` fallback |
| AADSTS50011 redirect URI mismatch | mcp-remote used a random port / `127.0.0.1`. Pin the port as the positional arg after the URL (`... /mcp 7778 ...`), let host default to `localhost`, and register `http://localhost:7778/oauth/callback` on the Kiro client. Register the `127.0.0.1` form too — Entra treats them as distinct. |
| Target won't sync | OpenAPI spec not in the bucket before target create (deploy.sh handles ordering) |

## Optional §5 — Cedar per-tool gating (not in the base stack)

To limit e.g. `send_mail` to an `Outlook.ReadWrite` role: create app roles (Phase 1
A.7), then add `AWS::BedrockAgentCore::PolicyEngine` + `AWS::BedrockAgentCore::Policy`
resources. Start `LOG_ONLY`, validate decisions in CloudWatch, switch to `ENFORCE`.
These are not included in the base template.
