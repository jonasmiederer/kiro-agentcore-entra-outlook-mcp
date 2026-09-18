# Outlook via MCP for Kiro users — Option A (no Lambda)

Delegated Outlook/Graph access for Kiro users through **AgentCore Gateway + Entra**,
with **Microsoft Graph attached as an OpenAPI target** and the Gateway performing the
on-behalf-of (OBO) token exchange itself — no Lambda, no interceptor.

Implements section 7 ("Simpler alternative: no Lambda") of the design doc, which is
copied to `docs/design-reference.md`. Everything is CloudFormation
(`AWS::BedrockAgentCore::*`).

## What deploys

| Resource | Role |
|---|---|
| `AWS::SecretsManager::Secret` | Entra API app client secret (only if you don't supply an existing ARN) |
| `AWS::BedrockAgentCore::OAuth2CredentialProvider` | `MicrosoftOauth2`, secret read from Secrets Manager (`EXTERNAL`) |
| `AWS::IAM::Role` | Gateway role — OBO token exchange + read secret + read OpenAPI spec |
| `AWS::BedrockAgentCore::Gateway` | `CUSTOM_JWT` inbound authorizer: Entra discovery URL, `allowedAudience` = API app, custom claim `azp` = Kiro client |
| `AWS::BedrockAgentCore::GatewayTarget` | Graph OpenAPI target, OAuth `TOKEN_EXCHANGE` (OBO) referencing the provider ARN |

Verified against the live CloudFormation resource schemas for
`AWS::BedrockAgentCore::*`: `OAuthGrantType` includes `TOKEN_EXCHANGE`, so OBO is
fully CFN-native. Availability may vary by region — deploy to a region where
AgentCore Gateway is supported.

## Files

```
templates/outlook-mcp-gateway.yaml   the stack
openapi/graph-me-openapi.json        read-only Graph /me slice (mail + calendar + profile)
scripts/deploy.sh                    bucket-first, upload spec, deploy stack
scripts/params.example.json          copy to params.json, fill Entra GUIDs + secret
docs/PHASE1-entra-setup.md           Entra portal setup → produces 2 GUIDs + secret
docs/PHASE2-kiro-and-verify.md       Kiro mcp.json + §8 verification checklist
docs/design-reference.md             the source research/design doc
```

## Run order

1. **Phase 1 (Entra):** follow `docs/PHASE1-entra-setup.md` → get `ApiAppClientId`,
   `KiroClientAppId`, `ApiAppClientSecret`.
2. `cp scripts/params.example.json scripts/params.json` and fill it in.
3. **Deploy:** `PROFILE=<your-aws-profile> REGION=<your-region> scripts/deploy.sh`
4. **Phase 2 (Kiro + verify):** wire Kiro `mcp.json` with the `GatewayUrl` output and
   run the verification checklist (`docs/PHASE2-kiro-and-verify.md`).

## Scope note

Default Graph scopes are **read-only** (`Mail.Read`, `Calendars.Read`, `User.Read`).
To add send/write, update three things together: the Entra API app delegated
permissions (+ admin consent), the `GraphScopes` parameter, and the OpenAPI spec
(add the `/me/sendMail` path).

Optional Cedar per-tool gating (design doc §5) is documented in
`docs/PHASE2-kiro-and-verify.md` but not in the base stack.
