variable "postmarkAccountToken" {
  description = "Postmark account-level API token"
  type        = string
  sensitive   = true
}

variable "serverNameBase" {
  description = "Human-readable prefix for the auto-generated unique server name"
  type        = string
  default     = "app"
}

variable "domain" {
  description = "Domain to verify in Postmark (must match the domain used by the deploy stack)"
  type        = string
}

variable "fromEmail" {
  description = "Sender address. If empty, defaults to auth@<domain>."
  type        = string
  default     = ""
}

variable "deliveryType" {
  description = "Postmark server delivery mode: 'live' or 'sandbox'."
  type        = string
  default     = "live"
  validation {
    condition     = contains(["live", "sandbox"], var.deliveryType)
    error_message = "deliveryType must be 'live' or 'sandbox'."
  }
}

variable "provisionDomain" {
  description = <<-EOT
    Whether this package should provision the postmark_domain resource for
    var.domain. A Postmark domain is ACCOUNT-scoped — there can only be one
    per Postmark account. Set true for the FIRST workspace that owns the
    domain (typically dev), false for every other workspace sharing the
    same Postmark account (staging, prod, ...). Workspaces with false=
    skip the domain resource entirely and the dnsRecord* outputs come
    back empty (the first workspace already published them).
  EOT
  type    = bool
  default = true
}
