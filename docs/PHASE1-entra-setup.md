# Phase 1 — Entra ID setup (in the portal / az CLI)

Work in your own Entra tenant (`<TenantId>`). You need an Entra admin who can
create app registrations and grant admin consent. Output: **two GUIDs + one client
secret** that go into `scripts/params.json`.

Two apps (design doc §1): an **API app** (the resource Kiro asks a token for, and
the OBO middle-tier that holds the secret) and a **public client app** (what Kiro
signs in as).

---

## A. API app — "Outlook MCP Gateway"

1. **Entra admin center → App registrations → New registration.**
   - Name: `Outlook MCP Gateway`
   - Supported account types: *Accounts in this organizational directory only*.
   - No redirect URI.
   - Register. **Copy the Application (client) ID → this is `ApiAppClientId`.**

2. **Expose an API.**
   - Left nav → *Expose an API* → *Add* next to Application ID URI → accept
     `api://<ApiAppClientId>`.
   - *Add a scope*:
     - Scope name: `access_as_user`
     - Who can consent: *Admins and users*
     - Admin consent display name/description: "Access Outlook as the signed-in user"
     - State: Enabled → Add scope.

3. **Force v2 access tokens** (so `iss` ends in `/v2.0` and the Gateway's discovery
   URL validates).
   - Left nav → *Manifest* → set `"requestedAccessTokenVersion": 2` → Save.
   - (In the new manifest editor this is under *Manage → Manifest*, `api` section.)

4. **Delegated Graph permissions** (start read-only).
   - *API permissions → Add a permission → Microsoft Graph → Delegated permissions*:
     `Mail.Read`, `Calendars.Read`, `User.Read`.
     (Add `Mail.ReadWrite` / `Calendars.ReadWrite` / `Mail.Send` later only when a
     write/send tool is in scope — and update `GraphScopes` in params + the OpenAPI
     spec together.)
   - Click **Grant admin consent for <tenant>** so OBO needs no per-user prompt.
     (Full step-by-step, incl. the tenant-wide consent URL, is in section C.)

5. **Client secret** (goes into AWS Secrets Manager, never into the template).
   - *Certificates & secrets → New client secret* → 24 months → Add.
   - **Copy the secret VALUE immediately → this is `ApiAppClientSecret`.**
   - (A certificate is stronger; a secret is fine for most setups. Using a cert
     requires the CFN provider to reference the cert path instead.)

6. **Let the Kiro client share consent.**
   - *Manifest* → add the Kiro client app ID (from section B) to
     `knownClientApplications: ["<KiroClientAppId>"]` → Save.
   - OR under *Expose an API → Authorized client applications* → Add the Kiro client
     ID and check `access_as_user`.

7. *(Optional, for §5 Cedar per-tool gating)* *App roles → Create app role*:
   `Outlook.Read`, `Outlook.ReadWrite` (Allowed member types: Users/Groups). Assign
   via the enterprise app. Prefer app roles over the `groups` claim (groups overage >200 drops the claim).

---

## B. Client app — "Kiro Outlook MCP client"

1. **App registrations → New registration.**
   - Name: `Kiro Outlook MCP client`
   - Account types: *this org only*.
   - Redirect URI: platform **Mobile and desktop applications**,
     `http://localhost:7778/oauth/callback` (Kiro pins host to localhost/127.0.0.1,
     scheme http). You can add more localhost ports later.
   - Register. **Copy the Application (client) ID → this is `KiroClientAppId`.**

2. **Mark it a public client.**
   - *Authentication → Advanced settings → Allow public client flows → Yes.*

3. **Delegated permission to the API app.**
   - *API permissions → Add a permission → APIs my organization uses →* search
     `Outlook MCP Gateway` → *Delegated permissions* → `access_as_user` → Add.
   - Grant admin consent (see section C) — or rely on step A6 combined consent.

4. **"Only Kiro users" — the primary control.**
   - *Entra admin center → Enterprise applications →* `Kiro Outlook MCP client` →
     *Properties → Assignment required? = Yes* → Save.
   - *Users and groups → Add user/group →* assign the **Kiro users** group.
   - Entra then refuses to issue tokens to anyone not assigned.
   - *(Optional)* Add a Conditional Access policy (compliant device / MFA) targeting
     this app.

---

## C. Grant admin consent (fixes "Need admin approval")

If sign-in shows **"Need admin approval … needs permission to access resources in
your organization that only an admin can grant"**, the tenant requires admin consent
for the Graph delegated scopes. This is a one-time, tenant-wide action by an admin
(Global Administrator, Privileged Role Administrator, or Cloud Application
Administrator). Users cannot self-consent to these scopes.

You must consent on **both** apps. Pick the portal path or the URL path.

### Path 1 — Portal buttons (recommended, most explicit)

1. **API app → Graph permissions.**
   - *App registrations →* `Outlook MCP Gateway` *→ API permissions.*
   - Verify each Graph permission's **Type = Delegated** (NOT Application —
     Application permissions can't do OBO and always need admin consent).
   - Click **Grant admin consent for `<tenant>`** → Yes.
   - The *Status* column should turn to green **"Granted for `<tenant>`"** for
     `Mail.Read`, `Calendars.Read`, `User.Read`.

2. **Kiro client app → the API scope.**
   - *App registrations →* `Kiro Outlook MCP client` *→ API permissions.*
   - Confirm `access_as_user` (delegated, under your API app) is listed.
   - Click **Grant admin consent for `<tenant>`** → Yes.

You need the **"Grant admin consent"** button to be enabled — it's greyed out for
non-privileged accounts. If it's greyed out, you are not an admin: send this doc (or
the URL below) to whoever administers the tenant.

### Path 2 — Tenant-wide admin-consent URL (one click, admin only)

Open this as an admin; it consents the Kiro client (and the API scope it chains to)
for the entire org in one step:

```
https://login.microsoftonline.com/<TenantId>/adminconsent?client_id=<KiroClientAppId>
```

Substitute your own tenant ID and Kiro client app ID, e.g.:

```
https://login.microsoftonline.com/<TenantId>/adminconsent?client_id=<KiroClientAppId>
```

After the admin approves, the consent prompt goes away for every assigned user; you
do **not** need to redeploy anything — reload the `001-outlook` MCP server and sign
do **not** need to redeploy anything — reload the `outlook` MCP server and sign
in again.
### Verify consent landed

- *Enterprise applications →* `Kiro Outlook MCP client` *→ Permissions* — the
  delegated Graph permissions appear under **"Admin consent"** with your tenant.
- *Enterprise applications →* `Outlook MCP Gateway` *→ Permissions* — `Mail.Read`,
  `Calendars.Read`, `User.Read` listed as admin-consented.

### Why it's needed here

The Kiro client requests `api://<ApiAppClientId>/access_as_user`; that token is then
used by AgentCore for the OBO exchange to Graph, which needs the API app's *delegated*
Graph scopes. Admin consent pre-authorizes those scopes so neither the interactive
sign-in nor the background OBO exchange hits a consent prompt (OBO cannot show a UI,
so an unconsented scope would fail the exchange with `interaction_required`).


## D. Fill in the deploy parameters

Fill `scripts/params.json` (copy from `params.example.json`):

```json
{
  "EntraTenantId": "<your tenant ID>",
  "ApiAppClientId": "<from A.1>",
  "KiroClientAppId": "<from B.1>",
  "ApiAppClientSecret": "<from A.5>"
}
```

Then run `scripts/deploy.sh`. The secret lands in Secrets Manager and
is read by the CFN `MicrosoftOauth2` provider (ClientSecretSource=EXTERNAL); it never
appears in the template or stack events.

> Note: `params.json` holds a live secret — it is gitignored. After a successful
> deploy you can delete the `ApiAppClientSecret` line (the value is already in
> Secrets Manager) and redeploys will reuse the existing secret.
