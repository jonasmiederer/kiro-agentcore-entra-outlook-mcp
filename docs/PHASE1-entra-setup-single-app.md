# Phase 1 (variant) — Entra ID setup with a SINGLE app registration

This is an alternative to `PHASE1-entra-setup.md`, which uses two app
registrations (an API/resource app and a public client app). Here you collapse
both roles into **one** app registration that is simultaneously:

- the **resource** Kiro asks a token for (it *exposes* `access_as_user` and holds
  the delegated Graph permissions), and
- the **public client** Kiro signs in as (it has the localhost redirect URI and
  public-client flows enabled), and
- the **OBO middle-tier** that holds the client secret and exchanges the user
  token for a Graph token.

Output: **one GUID + one client secret**. Because there is only one app,
`ApiAppClientId` and `KiroClientAppId` are the **same** GUID — you put that same
value in both parameters.

> When to use this. A single app is simpler to stand up (one registration, one
> consent, no `knownClientApplications` wiring) and is fine for a PoC or a small
> internal user group. The two-app split is the cleaner production posture: it
> lets you keep the secret-bearing resource separate from the public client, and
> it lets "Assignment required" gate *only* the client identity without touching
> the resource. See "Trade-offs" at the end.

---

## A. Create the one app — "Outlook MCP Gateway (Kiro)"

1. **Entra admin center → App registrations → New registration.**
   - Name: `Outlook MCP Gateway (Kiro)`
   - Supported account types: *Accounts in this organizational directory only*.
   - Redirect URI: platform **Mobile and desktop applications**,
     `http://localhost:7778/oauth/callback`. Also add
     `http://127.0.0.1:7778/oauth/callback` (Entra treats them as distinct; the
     bridge may use either). Kiro pins the host to localhost/127.0.0.1 over http.
   - Register. **Copy the Application (client) ID.** This ONE GUID is used for
     **both** `ApiAppClientId` and `KiroClientAppId` in `scripts/params.json`.

2. **Mark it a public client** (so the interactive PKCE sign-in works without a
   secret on the client side).
   - *Authentication → Advanced settings → Allow public client flows → Yes.*

3. **Expose an API** (this is the "resource" half).
   - Left nav → *Expose an API* → *Add* next to Application ID URI → accept
     `api://<AppClientId>`.
   - *Add a scope*:
     - Scope name: `access_as_user`
     - Who can consent: *Admins and users*
     - Admin consent display name/description: "Access Outlook as the signed-in user"
     - State: Enabled → Add scope.

4. **Force v2 access tokens** (so `iss` ends in `/v2.0` and the Gateway's
   discovery URL validates; a v1.0 token is rejected by issuer validation).
   - Left nav → *Manifest* → set `"requestedAccessTokenVersion": 2` → Save.
   - (In the new manifest editor this is under *Manage → Manifest*, `api` section.)

5. **Delegated Graph permissions** (start read-only).
   - *API permissions → Add a permission → Microsoft Graph → Delegated permissions*:
     `Mail.Read`, `Calendars.Read`, `User.Read`, `Mail.ReadWrite`, `Calendars.ReadWrite`, `Mail.Send`)

6. **Add the app's OWN API scope to itself.** This is the step that is unique to
   the single-app design: the app is both the client and the resource, so it must
   have delegated permission to the `access_as_user` scope it just exposed.
   - *API permissions → Add a permission → My APIs* (or *APIs my organization
     uses*) → select `Outlook MCP Gateway (Kiro)` (this same app) →
     *Delegated permissions* → `access_as_user` → Add.
   - You should now see, under this one app's *API permissions*: the Graph
     delegated permissions **and** `access_as_user` pointing at itself.

7. **Grant admin consent** (see section C). Because there is only one app, there
   is only one consent to grant — no combined-consent / `knownClientApplications`
   wiring is needed.

8. **Client secret** (goes into AWS Secrets Manager, never into the template).
   This backs the OBO exchange the Gateway performs.
   - *Certificates & secrets → New client secret* → 24 months → Add.
   - **Copy the secret VALUE immediately → this is `ApiAppClientSecret`.**
   - (A certificate is stronger; a secret is fine for most setups.)

9. **"Only Kiro users" — the access control.**
   - *Entra admin center → Enterprise applications →* `Outlook MCP Gateway (Kiro)`
     *→ Properties → Assignment required? = Yes* → Save.
   - *Users and groups → Add user/group →* assign the **Kiro users** group.
   - Entra then refuses to issue tokens to anyone not assigned.
   - *(Optional)* Add a Conditional Access policy (compliant device / MFA)
     targeting this app.

10. *(Optional, for per-tool Cedar gating)* *App roles → Create app role*:
    `Outlook.Read`, `Outlook.ReadWrite`. Prefer app roles over the `groups` claim
    (groups overage >200 drops the claim).

---

## B. What is NOT needed (versus the two-app guide)

Because a single registration plays both roles, you can **skip** the following
steps from `PHASE1-entra-setup.md`:

- **No second app registration** ("Kiro Outlook MCP client" is not created).
- **No `knownClientApplications` / Authorized client applications** entry. In the
  two-app design that line lets one consent cover both apps; with one app there is
  nothing to authorize — the app already trusts itself.
- **No second admin-consent pass.** You consent once, on this single app.

Everything else — expose-an-API, v2 token version, delegated Graph permissions,
public-client flows, the localhost redirect, "Assignment required", the client
secret — still applies, just consolidated onto the one app.

---

## C. Grant admin consent (fixes "Need admin approval")

If sign-in shows **"Need admin approval … needs permission to access resources in
your organization that only an admin can grant"**, the tenant requires admin
consent for the Graph delegated scopes. This is a one-time, tenant-wide action by
an admin (Global Administrator, Privileged Role Administrator, or Cloud
Application Administrator). Users cannot self-consent to these scopes.

### Path 1 — Portal button (recommended)

- *App registrations →* `Outlook MCP Gateway (Kiro)` *→ API permissions.*
- Verify each Graph permission's **Type = Delegated** (NOT Application —
  Application permissions can't do OBO and always need admin consent).
- Confirm `access_as_user` (delegated, under this same app) is listed alongside
  the Graph permissions.
- Click **Grant admin consent for `<tenant>`** → Yes.
- The *Status* column should turn green **"Granted for `<tenant>`"** for
  `Mail.Read`, `Calendars.Read`, `User.Read`, and `access_as_user`.

If the **Grant admin consent** button is greyed out you are not an admin — send
this doc (or the URL below) to whoever administers the tenant.

### Path 2 — Tenant-wide admin-consent URL (one click, admin only)

Open this as an admin; it consents the single app (and the API scope it chains to)
for the entire org in one step. `<AppClientId>` is the same GUID from A.1:

```
https://login.microsoftonline.com/<TenantId>/adminconsent?client_id=<AppClientId>
```

After the admin approves, the consent prompt goes away for every assigned user;
you do **not** need to redeploy anything — reload the `outlook` MCP server and
sign in again.

### Verify consent landed

- *Enterprise applications →* `Outlook MCP Gateway (Kiro)` *→ Permissions* —
  `Mail.Read`, `Calendars.Read`, `User.Read` (and `access_as_user`) listed as
  admin-consented for your tenant.

### Why it's needed here

Kiro requests `api://<AppClientId>/access_as_user`; that user token is then used
by AgentCore for the OBO exchange to Graph, which needs the app's *delegated*
Graph scopes. Admin consent pre-authorizes those scopes so neither the interactive
sign-in nor the background OBO exchange hits a consent prompt (OBO cannot show a
UI, so an unconsented scope would fail the exchange with `interaction_required`).

---

## D. Fill in the deploy parameters

The deploy template and `deploy.sh` are **unchanged** — they still take both
`ApiAppClientId` and `KiroClientAppId`. In this variant you set **both to the same
GUID** (the one app ID from A.1):

```json
{
  "EntraTenantId": "<your tenant ID>",
  "ApiAppClientId": "<app ID from A.1>",
  "KiroClientAppId": "<same app ID from A.1>",
  "ApiAppClientSecret": "<secret value from A.8>"
}
```

Why this still works with no template change:

- The Gateway's `AllowedAudience` is `ApiAppClientId`. Entra sets the token
  `aud` to the app the scope belongs to — this app — so `aud` matches.
- The Gateway's custom claim requires `azp EQUALS KiroClientAppId`. Entra sets
  `azp` to the calling client — also this app. With one app, `azp == aud ==` the
  single GUID, so the `azp` check passes when both params hold that GUID.
- The OBO provider uses `ApiAppClientId` + the secret as the confidential
  middle-tier. The app calling its own exposed API and then performing OBO with
  its own credential is a valid delegated flow.

Then run `scripts/deploy.sh`. The secret lands in Secrets Manager and is read by
the CFN `MicrosoftOauth2` provider (`ClientSecretSource=EXTERNAL`); it never
appears in the template or stack events.

> Note: `params.json` holds a live secret — it is gitignored. After a successful
> deploy you can delete the `ApiAppClientSecret` line (the value is already in
> Secrets Manager) and redeploys will reuse the existing secret.

---

## Trade-offs: single app vs. two apps

| Concern | Single app (this doc) | Two apps (`PHASE1-entra-setup.md`) |
|---|---|---|
| Registrations to manage | 1 | 2 |
| Consent | One pass, no `knownClientApplications` | Two apps; combined consent via authorized-client wiring |
| Secret exposure | The same identity that users sign in as also holds the OBO secret | Secret lives only on the resource app, separate from the public client |
| `aud` vs `azp` | Identical GUID; the `azp` check is effectively "is it this app" | Distinct GUIDs; `azp` proves the token was minted specifically for the Kiro client |
| "Only Kiro users" gate | Applied to the one combined app | Applied to the public client only, leaving the resource app untouched |
| Best for | PoC, small internal group, fastest setup | Production; cleaner separation of client vs. resource |

Both produce the same runtime behavior for Kiro: an assigned user signs in, gets a
v2 token for `access_as_user`, and the Gateway validates it and performs OBO to
Graph. The choice is about how much you want to separate the client identity from
the secret-bearing resource identity.
