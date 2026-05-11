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

output "dnsRecordDkimHost" {
  value = postmark_domain.domain.dkim_pending_host
}

output "dnsRecordDkimType" {
  value = "TXT"
}

output "dnsRecordDkimValue" {
  value = postmark_domain.domain.dkim_pending_text_value
}

output "dnsRecordReturnPathHost" {
  value = postmark_domain.domain.return_path_domain
}

output "dnsRecordReturnPathType" {
  value = "CNAME"
}

output "dnsRecordReturnPathValue" {
  value = postmark_domain.domain.return_path_domain_cname_value
}

output "dnsRecordsPostmark" {
  value = jsonencode([
    {
      name  = postmark_domain.domain.dkim_pending_host
      type  = "TXT"
      value = postmark_domain.domain.dkim_pending_text_value
    },
    {
      name  = postmark_domain.domain.return_path_domain
      type  = "CNAME"
      value = postmark_domain.domain.return_path_domain_cname_value
    }
  ])
}
