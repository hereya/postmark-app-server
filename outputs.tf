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

output "dnsRecordDkimHost" {
  value = nonsensitive(postmark_domain.domain.dkim_pending_host)
}

output "dnsRecordDkimType" {
  value = "TXT"
}

output "dnsRecordDkimValue" {
  value = nonsensitive(postmark_domain.domain.dkim_pending_text_value)
}

output "dnsRecordReturnPathHost" {
  value = nonsensitive(postmark_domain.domain.return_path_domain)
}

output "dnsRecordReturnPathType" {
  value = "CNAME"
}

output "dnsRecordReturnPathValue" {
  value = nonsensitive(postmark_domain.domain.return_path_domain_cname_value)
}

output "dnsRecordsPostmark" {
  value = jsonencode([
    {
      name  = nonsensitive(postmark_domain.domain.dkim_pending_host)
      type  = "TXT"
      value = nonsensitive(postmark_domain.domain.dkim_pending_text_value)
    },
    {
      name  = nonsensitive(postmark_domain.domain.return_path_domain)
      type  = "CNAME"
      value = nonsensitive(postmark_domain.domain.return_path_domain_cname_value)
    }
  ])
}
