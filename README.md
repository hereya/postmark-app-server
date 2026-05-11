# Postmark App Server

Provisions a per-app Postmark server (with a unique, auto-generated name) and registers a domain for verification in Postmark. Unlike `hereya/postmark-server`, this package does **not** manage DNS records — the required DKIM and return-path records are exposed as outputs (prefixed `dnsRecord*`) so the caller (typically a deploy stack that owns the domain's DNS zone) can configure them.

The Postmark server API token is stored as an AWS SSM `SecureString` parameter, and an IAM policy document granting read access to that parameter is exposed via `iamPolicyPostmark`.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `postmarkAccountToken` | string (sensitive) | — | Postmark account-level API token. |
| `serverNameBase` | string | `app` | Human-readable prefix for the auto-generated unique server name. |
| `domain` | string | — | Domain to verify in Postmark. Must match the domain used by the deploy stack. |
| `fromEmail` | string | `""` | Sender address. Defaults to `auth@<domain>` if empty. |
| `deliveryType` | string | `live` | Postmark server delivery mode: `live` or `sandbox`. |

## Outputs

| Name | Description |
|------|-------------|
| `postmarkServerTokenArn` | ARN of the SSM `SecureString` parameter holding the Postmark server API token. |
| `postmarkFromEmail` | Resolved sender email address. |
| `iamPolicyPostmark` | JSON-encoded IAM policy document granting `ssm:GetParameter` on the token parameter plus `kms:Decrypt` scoped to SSM via `kms:ViaService`. |
| `dnsRecordDkimHost` | DKIM record host (name). |
| `dnsRecordDkimType` | DKIM record type (`TXT`). |
| `dnsRecordDkimValue` | DKIM record value. |
| `dnsRecordReturnPathHost` | Return-path record host (name). |
| `dnsRecordReturnPathType` | Return-path record type (`CNAME`). |
| `dnsRecordReturnPathValue` | Return-path record value. |
| `dnsRecordsPostmark` | JSON-encoded array of all DNS records needed for verification. |

## DNS

The domain is registered with Postmark but verification requires DNS records to be published on the domain's authoritative zone. This package exposes those records as outputs (all prefixed `dnsRecord*`) — the caller is responsible for creating them. This decouples the Postmark package from any specific DNS provider (Route53, Cloudflare, etc.).
