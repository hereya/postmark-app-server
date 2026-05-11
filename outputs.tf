output "postmarkServerTokenArn" {
  value = aws_ssm_parameter.postmark_server_key.arn
}

output "postmarkFromEmail" {
  value = local.resolved_from_email
}

output "iamPolicyPostmark" {
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.postmark_server_key.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com" }
        }
      }
    ]
  })
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
