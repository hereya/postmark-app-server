terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    postmark = {
      source  = "shebang-labs/postmark"
      version = "0.2.4"
    }
  }
}

provider "aws" {}
provider "random" {}
provider "postmark" {
  account_token = var.postmarkAccountToken
}

data "aws_region" "current" {}

# Route 53 hosted zone lookup — only when we're in auto-subdomain mode.
# The workspace exposes `defaultRootDomain` (e.g. "example.com") and we
# look up the zone id by name. Public zones only; if the user runs Route
# 53 private zones they should pin var.domain and manage DNS themselves.
data "aws_route53_zone" "root" {
  count        = local.manage_dns_in_route53 ? 1 : 0
  name         = var.defaultRootDomain
  private_zone = false
}

locals {
  # In auto-subdomain mode, if the user didn't pin var.subdomainName, fall
  # back to a random_pet — keeps multiple workspaces sharing one root
  # domain from colliding on a hardcoded label. The random value is keyed
  # on var.defaultRootDomain so it stays stable across applies for a
  # given workspace.
  effective_subdomain = (
    var.subdomainName != ""
      ? var.subdomainName
      : random_pet.subdomain.id
  )

  # Effective domain — see variables.tf for the two modes:
  #   external DNS  (var.domain set)
  #   auto-subdomain on Route 53 (var.domain empty, defaultRootDomain from workspace)
  effective_domain = (
    var.domain != ""
      ? var.domain
      : (
        var.defaultRootDomain != ""
          ? "${local.effective_subdomain}.${var.defaultRootDomain}"
          : ""
      )
  )

  # When the user did not pin var.domain AND a root domain is available
  # (workspace exposed one), the package automates DNS in Route 53 by
  # discovering the hosted zone via data.aws_route53_zone.
  manage_dns_in_route53 = var.domain == "" && var.defaultRootDomain != ""

  resolved_from_email = (
    var.fromEmail != ""
      ? var.fromEmail
      : "auth@${local.effective_domain}"
  )
}

# Validation: at least one of the two modes must be fully configured.
# Triggers a clear plan-time error rather than letting Postmark see "".
check "domain_configured" {
  assert {
    condition     = local.effective_domain != ""
    error_message = "Set either var.domain (external DNS) OR var.defaultRootDomain (auto-subdomain on Route 53). var.subdomainName is optional in the latter — leave empty to auto-generate."
  }
}

resource "random_pet" "server_suffix" {
  length = 4
}

# Random subdomain prefix used when the user does not pin var.subdomainName
# in auto-subdomain mode. Two-word pet name (e.g. "happy-otter") keeps the
# label short, DNS-safe, and reasonably unique.
#
# The keeper ties the random value to var.defaultRootDomain so the same
# workspace gets the same subdomain across applies. Changing the root
# domain (or destroying + recreating) regenerates a fresh subdomain.
resource "random_pet" "subdomain" {
  length    = 2
  separator = "-"
  keepers = {
    root_domain = var.defaultRootDomain
  }
}

resource "postmark_server" "server" {
  name          = "${var.serverNameBase}-${random_pet.server_suffix.id}"
  delivery_type = var.deliveryType
}

resource "postmark_domain" "domain" {
  # provisionDomain=false skips the resource entirely — for workspaces
  # sharing one Postmark account where the domain has already been
  # registered by another workspace.
  count = var.provisionDomain ? 1 : 0
  name  = local.effective_domain

  # The shebang-labs/postmark provider's Update for `name` is a silent
  # no-op (see README); forcing replacement via terraform_data trigger
  # below is how we recover correct destroy+create semantics. We can't
  # use `for_each = toset([local.effective_domain])` because that local
  # is known-only-after-apply when the subdomain is auto-generated
  # (random_pet) — Terraform requires for_each keys to be statically
  # known at plan time.
  lifecycle {
    replace_triggered_by = [terraform_data.domain_trigger]
  }
}

# Stable replacement trigger for postmark_domain.domain. terraform_data is
# the built-in null-replacement: changing any value in `triggers_replace`
# causes terraform_data to be replaced, which in turn forces replacement
# of any resource that references it via `replace_triggered_by`.
resource "terraform_data" "domain_trigger" {
  triggers_replace = [local.effective_domain]
}

# ---------------------------------------------------------------------------
# Route 53 records — only when the package is BOTH owning the registration
# AND the workspace provided a hosted zone.
#
# Two records:
#   • DKIM TXT at <selector>._domainkey.<effective_domain>
#   • Return-path CNAME at pm-bounces.<effective_domain> -> pm.mtasv.net
#
# The DKIM TTL is 300s so the user can iterate quickly if they have to
# (Postmark's verification poll cycle is also ~5min). Return-path is set
# from the provider's value with a fallback to Postmark's well-known
# default ("pm.mtasv.net") since shebang-labs/postmark v0.2.4's
# return_path_domain_cname_value is sometimes empty on Read.
# ---------------------------------------------------------------------------

resource "aws_route53_record" "postmark_dkim" {
  count = local.manage_dns_in_route53 && var.provisionDomain ? 1 : 0

  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = nonsensitive(postmark_domain.domain[0].dkim_pending_host)
  type    = "TXT"
  ttl     = 300
  records = [nonsensitive(postmark_domain.domain[0].dkim_pending_text_value)]
}

resource "aws_route53_record" "postmark_return_path" {
  count = local.manage_dns_in_route53 && var.provisionDomain ? 1 : 0

  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = "pm-bounces.${local.effective_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [
    coalesce(
      try(
        nonsensitive(postmark_domain.domain[0].return_path_domain_cname_value),
        null,
      ),
      "pm.mtasv.net",
    )
  ]
}

# ---------------------------------------------------------------------------
# Trigger Postmark's domain verification immediately after the Route 53
# records are created. Without this, Postmark's own poll cycle takes ~5
# minutes to discover the records. The verifyDkim and verifyReturnPath
# endpoints force an immediate authoritative DNS lookup on Postmark's side.
#
# Only runs in auto-Route53 mode — in external-DNS mode the user controls
# when their records become live, so triggering verification eagerly would
# just produce "DNS not found" responses.
#
# The replace_triggers ensure the check re-runs if either record's content
# changes or the postmark_domain id changes. Failures are non-fatal — if
# Postmark says "not yet propagated" the next poll cycle catches up.
# ---------------------------------------------------------------------------
resource "terraform_data" "trigger_postmark_verification" {
  count = local.manage_dns_in_route53 && var.provisionDomain ? 1 : 0

  triggers_replace = [
    aws_route53_record.postmark_dkim[0].id,
    aws_route53_record.postmark_return_path[0].id,
    postmark_domain.domain[0].id,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    # Token + domain id passed via env so they don't leak into the rendered
    # command (ps listing etc.).
    environment = {
      POSTMARK_TOKEN = var.postmarkAccountToken
      DOMAIN_ID      = postmark_domain.domain[0].id
    }
    command = <<-EOT
      set -u
      # Brief wait for Route 53's authoritative servers to serve the new
      # records before pinging Postmark — usually a few seconds, 20s is a
      # safe upper bound.
      sleep 20
      for endpoint in verifyDkim verifyReturnPath; do
        echo "[postmark] Triggering $endpoint for domain $DOMAIN_ID..."
        curl -fsS -X PUT \
          -H "Accept: application/json" \
          -H "Content-Type: application/json" \
          -H "X-Postmark-Account-Token: $POSTMARK_TOKEN" \
          "https://api.postmarkapp.com/domains/$DOMAIN_ID/$endpoint" \
          | head -c 300 \
          || echo "  (non-fatal: Postmark will auto-verify on its own poll cycle)"
        echo
      done
    EOT
  }
}

resource "aws_ssm_parameter" "postmark_server_key" {
  name        = "/postmark_app_server/${random_pet.server_suffix.id}/server_key"
  description = "Postmark server API key for ${postmark_server.server.name}"
  type        = "SecureString"
  value       = postmark_server.server.apitokens[0]
}
