# Postmark server API token. We output the SSM SecureString ARN; hereya
# auto-resolves SSM SecureString ARNs and substitutes the decrypted value
# into the consumer's env, so by the time downstream code reads
# `postmarkServerToken` it holds the actual token (not an ARN). Consumers
# therefore do NOT need any ssm:GetParameter / kms:Decrypt IAM permission
# — hereya itself handles the SSM read on the dev/deploy side using its
# own role.
output "postmarkServerToken" {
  value = aws_ssm_parameter.postmark_server_key.arn
}

output "postmarkFromEmail" {
  value = local.resolved_from_email
}

# --- DNS records (all dnsRecord* prefixed -- user-actionable) ---
#
# The Postmark provider marks the DKIM and return-path attributes as
# sensitive defensively, but they are PUBLIC DNS records by nature --
# the user must publish them in their DNS zone. nonsensitive() unwraps
# them so they appear in `tofu output` and `hereya env`.
#
# When provisionDomain=false (subsequent workspaces sharing the same
# Postmark account), the domain resource has count=0, so accessing
# index [0] would error at apply time. The locals + try() pattern
# below returns "" in that case — the user already has the DNS records
# from the first workspace's apply.

locals {
  # postmark_domain.domain is `for_each`-keyed on var.domain (so a domain
  # change forces an address change → destroy+create, sidestepping the
  # provider's broken in-place Update). The collection's only element
  # is at key var.domain; if provisionDomain=false the map is empty and
  # try() returns the empty-string fallback.
  _dkim_host_raw  = try(nonsensitive(postmark_domain.domain[var.domain].dkim_pending_host), "")
  _dkim_value_raw = try(nonsensitive(postmark_domain.domain[var.domain].dkim_pending_text_value), "")
  _rp_host_raw    = try(nonsensitive(postmark_domain.domain[var.domain].return_path_domain), "")
  _rp_value_raw   = try(nonsensitive(postmark_domain.domain[var.domain].return_path_domain_cname_value), "")

  # shebang-labs/postmark returns `dkim_pending_host` as a full FQDN
  # but `return_path_domain` as just the relative prefix (e.g.
  # "pm-bounces"). Normalize the return-path to an FQDN so both DNS
  # records can be copied straight into a DNS provider's UI without
  # the user having to remember which is relative-vs-absolute.
  dkim_host  = local._dkim_host_raw
  dkim_value = local._dkim_value_raw
  rp_value   = local._rp_value_raw
  rp_host = local._rp_host_raw == "" ? "" : (
    endswith(local._rp_host_raw, var.domain)
      ? local._rp_host_raw
      : "${local._rp_host_raw}.${var.domain}"
  )
}

output "dnsRecordDkimHost" {
  value = local.dkim_host
}

output "dnsRecordDkimType" {
  value = "TXT"
}

output "dnsRecordDkimValue" {
  value = local.dkim_value
}

output "dnsRecordReturnPathHost" {
  value = local.rp_host
}

output "dnsRecordReturnPathType" {
  value = "CNAME"
}

output "dnsRecordReturnPathValue" {
  value = local.rp_value
}

output "dnsRecordsPostmark" {
  value = jsonencode(
    var.provisionDomain
      ? [
          { name = local.dkim_host, type = "TXT",   value = local.dkim_value },
          { name = local.rp_host,   type = "CNAME", value = local.rp_value },
        ]
      : []
  )
}
