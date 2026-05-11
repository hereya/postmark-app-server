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

  # shebang-labs/postmark's `return_path_domain` is unreliable: sometimes
  # it returns the relative prefix ("pm-bounces"), sometimes it returns
  # empty. The CNAME target (`return_path_domain_cname_value`) more
  # consistently returns "pm.mtasv.net". Since Postmark's DEFAULT
  # return-path setup is always `pm-bounces.<domain>` -> pm.mtasv.net,
  # we synthesize the FQDN ourselves when the provider hands us an empty
  # or relative value, and fall back to the well-known CNAME target if
  # that's empty too. Result: dnsRecordReturnPathHost / Value are always
  # paste-into-DNS ready for any user.
  #
  # The DKIM host always comes through fully-qualified, so it just passes
  # through.
  dkim_host  = local._dkim_host_raw
  dkim_value = local._dkim_value_raw

  rp_host = (
    local._rp_host_raw == ""
      ? (var.provisionDomain ? "pm-bounces.${var.domain}" : "")
      : (
        endswith(local._rp_host_raw, var.domain)
          ? local._rp_host_raw
          : "${local._rp_host_raw}.${var.domain}"
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
