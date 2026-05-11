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

locals {
  resolved_from_email = var.fromEmail != "" ? var.fromEmail : "auth@${var.domain}"
}

resource "random_pet" "server_suffix" {
  length = 4
}

resource "postmark_server" "server" {
  name          = "${var.serverNameBase}-${random_pet.server_suffix.id}"
  delivery_type = var.deliveryType
}

resource "postmark_domain" "domain" {
  # Conditional: only the FIRST workspace per Postmark account creates this.
  # Subsequent workspaces sharing the same account set provisionDomain=false
  # because Postmark domains are account-scoped (one per account, total),
  # not workspace-scoped — trying to "create" an already-existing one
  # triggers an inconsistent-state error in shebang-labs/postmark v0.2.4.
  count = var.provisionDomain ? 1 : 0

  name = var.domain

  # Even on the workspace that DOES own the domain, `shebang-labs/postmark`
  # v0.2.4 has a refresh bug: on subsequent applies the computed DKIM /
  # verification attributes diverge from what Create returned, and the
  # provider's refresh path reports "Root object was present, but now
  # absent". Once the domain is registered the first time its identity
  # is stable (the `name`), so we tell Tofu not to reconcile it. The
  # dnsRecord* outputs were captured on first apply and don't change.
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_ssm_parameter" "postmark_server_key" {
  name        = "/postmark_app_server/${random_pet.server_suffix.id}/server_key"
  description = "Postmark server API key for ${postmark_server.server.name}"
  type        = "SecureString"
  value       = postmark_server.server.apitokens[0]
}
