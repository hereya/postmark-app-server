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

# Tracks the domain name a level above the postmark_domain resource. When
# var.domain changes, this resource's `input` changes, which triggers a
# REPLACE (destroy + create) on postmark_domain.domain via the
# replace_triggered_by lifecycle below — bypassing the provider's broken
# in-place Update that silently returns success without actually renaming
# the domain in the Postmark account.
resource "terraform_data" "domain_marker" {
  count = var.provisionDomain ? 1 : 0
  input = var.domain
}

resource "postmark_domain" "domain" {
  # Conditional: only the FIRST workspace per Postmark account creates this.
  # Subsequent workspaces sharing the same account set provisionDomain=false
  # because Postmark domains are account-scoped (one per account, total),
  # not workspace-scoped — trying to "create" an already-existing one
  # triggers an inconsistent-state error in shebang-labs/postmark v0.2.4.
  count = var.provisionDomain ? 1 : 0

  name = var.domain

  lifecycle {
    # shebang-labs/postmark v0.2.4's Update operation for postmark_domain
    # is a no-op at the API level: Tofu sees the diff as in-place
    # ("name: brainumber.app -> dev.brainumber.app"), the provider claims
    # success, but the Postmark account is never actually rebranded.
    # Force a destroy-then-create when var.domain changes, which uses the
    # provider's Delete + Create paths (both of which DO work correctly).
    replace_triggered_by = [terraform_data.domain_marker]
  }
}

resource "aws_ssm_parameter" "postmark_server_key" {
  name        = "/postmark_app_server/${random_pet.server_suffix.id}/server_key"
  description = "Postmark server API key for ${postmark_server.server.name}"
  type        = "SecureString"
  value       = postmark_server.server.apitokens[0]
}
