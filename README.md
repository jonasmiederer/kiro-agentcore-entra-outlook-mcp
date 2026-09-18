# Outlook MCP Gateway for Kiro

Give Kiro delegated access to a user's Outlook mail and calendar through an
**AgentCore Gateway** fronted by **Microsoft Entra**. Microsoft Graph is attached
directly as an **OpenAPI target**, and the Gateway performs the on-behalf-of (OBO)
token exchange itself — no Lambda and no custom interceptor to build or maintain.

Everything is defined in CloudFormation (`AWS::BedrockAgentCore::*`). The full
research and design writeup lives in `docs/design-reference.md`.

## How it works

Kiro authenticates the user against Entra and sends the resulting token to the
AgentCore Gateway. The Gateway validates that token (`CUSTOM_JWT` inbound
authorizer), exchanges it for a Microsoft Graph token via OBO, and calls Graph on
the user's behalf using the attached OpenAPI target. The user only ever sees their
own mailbox and calendar, scoped to the Graph permissions you grant.

## What deploys

| Resource | Role |
|---|---|
| `AWS::SecretsManager::Secret` | Entra API app client secret (only if you don't supply an existing ARN) |
| `AWS::BedrockAgentCore::OAuth2CredentialProvider` | `MicrosoftOauth2`, secret read from Secrets Manager (`EXTERNAL`) |
| `AWS::IAM::Role` | Gateway role — OBO token exchange + read secret + read OpenAPI spec |
| `AWS::BedrockAgentCore::Gateway` | `CUSTOM_JWT` inbound authorizer: Entra discovery URL, `allowedAudience` = API app, custom claim `azp` = Kiro client |
| `AWS::BedrockAgentCore::GatewayTarget` | Graph OpenAPI target, OAuth `TOKEN_EXCHANGE` (OBO) referencing the provider ARN |

OBO is fully CloudFormation-native here: the `AWS::BedrockAgentCore::*` schemas
expose `TOKEN_EXCHANGE` as an `OAuthGrantType`, so no custom code is needed.
Availability varies by region — deploy to a region where AgentCore Gateway is
supported.

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
