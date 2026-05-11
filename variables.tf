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

# ---------------------------------------------------------------------------
# Domain inputs.
#
# Two modes:
#   A. External DNS. The user sets `domain` to a specific value (e.g.
#      "brainumber.app"). The package treats DNS as managed elsewhere —
#      it registers the domain in Postmark and emits the records the user
#      needs to add to their DNS provider.
#
#   B. Auto-subdomain on Route 53. The user leaves `domain` empty and sets
#      `subdomainName`. The package computes
#         effective_domain = $${subdomainName}.$${defaultRootDomain}
#      The `defaultRootDomain` comes from the workspace env (a hereya
#      devenv that owns a Route 53 hosted zone exposes it); the package
#      looks up the zone via data.aws_route53_zone and writes the DKIM +
#      return-path records there automatically. No manual DNS work.
# ---------------------------------------------------------------------------

variable "domain" {
  description = <<-EOT
    Explicit custom domain. When set, takes precedence over the auto-
    subdomain path and the package assumes the user manages DNS
    externally. Leave empty to use $${subdomainName}.$${defaultRootDomain}
    with automatic Route 53 record creation.
  EOT
  type    = string
  default = ""
}

variable "subdomainName" {
  description = <<-EOT
    Subdomain label used when var.domain is empty. Combined with
    var.defaultRootDomain to form the effective domain. Pick something
    short and DNS-safe per workspace (e.g. "myapp-dev", "myapp-staging").
    Leave empty to auto-generate a random collision-safe subdomain
    (random_pet) — useful for ephemeral workspaces / preview envs.
  EOT
  type    = string
  default = ""
}

variable "defaultRootDomain" {
  description = <<-EOT
    Workspace-owned root domain (e.g. "example.com") backed by a Route 53
    hosted zone. Typically auto-populated from the hereya workspace env —
    the user doesn't normally set this in hereyavars. The package looks
    up the hosted zone by name via data.aws_route53_zone and uses it for
    automatic DKIM + return-path record creation in subdomain mode.
  EOT
  type    = string
  default = ""
}

variable "fromEmail" {
  description = "Sender address. If empty, defaults to auth@<effective_domain>."
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
    Whether this package should provision the postmark_domain resource
    for the effective domain. A Postmark domain is ACCOUNT-scoped — there
    can only be one per Postmark account. Set true for the FIRST
    workspace that owns the domain, false for every other workspace
    sharing the same Postmark account.
  EOT
  type    = bool
  default = true
}
