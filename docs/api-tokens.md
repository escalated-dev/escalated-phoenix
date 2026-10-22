# API tokens

Admins can issue API tokens for the JSON ticket API at
`/support/admin/api-tokens` (the shared `Admin/ApiTokens/Index` page). A token
lets an integration call `/support/api/v1/tickets/*` as the agent who owns it.
This is escalated-laravel's `ApiToken`.

## Turning it on

Tokens are opt-in. Mount the API and turn them on:

```elixir
config :escalated,
  api_enabled: true,          # or escalated_routes("/support", api: true)
  api_tokens_enabled: true
```

Until `api_tokens_enabled` is `true`, admins can still manage tokens, the page
shows the API as disabled, and the API ignores them. Hosts that authenticate
the API themselves (`current_user` from their pipeline, or
`:api_token_validator`) keep working either way: a bearer value Escalated did
not issue is always handed to `:api_token_validator`.

Run the migration `20261026000001_create_api_tokens` first. It creates the
tenant-owned `api_tokens` table on SQLite, PostgreSQL and MySQL.

## Tokens

- A token is 64 hex characters (32 random bytes). Only its SHA-256 digest is
  stored. The plain text is shown once, in the flash after creating it
  (`flash.plain_text_token`). A JSON client gets it in the `201` response
  instead.
- Each token belongs to an agent (a host user who passes the agent check) and
  carries abilities: `agent`, `admin`, or `*` for both. The ticket API needs
  `agent` (or `*`).
- A token can expire after 1 to 365 days, or never.
- `last_used_at` and `last_used_ip` are recorded at most every five minutes.
- Admins can rename a token, change its abilities, or revoke (delete) it.

## Calling the API

```
Authorization: Bearer <token>
```

| Situation | Answer |
|---|---|
| Valid token with `agent` or `*` | The request runs as the owner |
| Expired token | 401 `Token has expired.` |
| Owner no longer exists | 401 `Token owner not found.` |
| Token without `agent` (an `admin`-only token) | 403 `Insufficient permissions.` |
| Owner is no longer an agent | 403 |
| Revoked or unknown token, with no `:api_token_validator` that accepts it | 401 |

Ticket visibility, tenant membership and reply authorship are the owner's, as
if the owner were signed in.
