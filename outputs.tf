# Postmark server API token. We output the SSM SecureString ARN; hereya
# auto-resolves SSM SecureString ARNs and substitutes the decrypted value
# into the consumer's env, so by the time downstream code reads
# `postmarkServerToken` it holds the actual token (not an ARN).
output "postmarkServerToken" {
  value = aws_ssm_parameter.postmark_server_key.arn
}

output "postmarkFromEmail" {
  value = local.resolved_from_email
}

# The domain that was actually used (after the var.domain / subdomain
# resolution). Consumers building user-visible URLs / sender addresses
# can read this rather than guessing which input was set.
output "effectiveDomain" {
  value = local.effective_domain
}

# The subdomain label only (e.g. "happy-otter" or whatever the user
# pinned). Empty in external-DNS mode. Downstream packages can read this
# to align CloudFront/ACM with the same generated value so the entire
# stack shares one effective domain.
output "effectiveSubdomain" {
  value = var.domain != "" ? "" : local.effective_subdomain
}

# --- DNS records (all dnsRecord* prefixed) ---
#
# In external-DNS mode (var.domain set), these tell the user what to
# add in their DNS provider. In Route 53 mode (auto-subdomain), the
# records are already created in the workspace's hosted zone and the
# user doesn't need to do anything — the outputs are still emitted as
# informational so an admin can verify what got created.
#
# Provider quirks handled:
#   • `return_path_domain` may come back as just "pm-bounces" (relative)
#     or empty. We synthesize the FQDN ourselves.
#   • `return_path_domain_cname_value` may come back empty. Default to
#     Postmark's well-known "pm.mtasv.net".

locals {
  _dkim_host_raw  = try(nonsensitive(postmark_domain.domain[local.effective_domain].dkim_pending_host), "")
  _dkim_value_raw = try(nonsensitive(postmark_domain.domain[local.effective_domain].dkim_pending_text_value), "")
  _rp_host_raw    = try(nonsensitive(postmark_domain.domain[local.effective_domain].return_path_domain), "")
  _rp_value_raw   = try(nonsensitive(postmark_domain.domain[local.effective_domain].return_path_domain_cname_value), "")

  dkim_host  = local._dkim_host_raw
  dkim_value = local._dkim_value_raw

  rp_host = (
    local._rp_host_raw == ""
      ? (var.provisionDomain && local.effective_domain != "" ? "pm-bounces.${local.effective_domain}" : "")
      : (
        endswith(local._rp_host_raw, local.effective_domain)
          ? local._rp_host_raw
          : "${local._rp_host_raw}.${local.effective_domain}"
      )
  )
  rp_value = (
    local._rp_value_raw == ""
      ? (var.provisionDomain ? "pm.mtasv.net" : "")
      : local._rp_value_raw
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
