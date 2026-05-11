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
  # Keyed on var.domain (rather than `count`) so a change to var.domain
  # changes the resource's ADDRESS in state — old key is dropped, new
  # key is added. Tofu's only path through this is destroy+create, which
  # uses the provider's Delete + Create methods (both of which actually
  # talk to the Postmark API). shebang-labs/postmark v0.2.4's Update is
  # a silent no-op — we route around it entirely.
  #
  # Conditional: only the FIRST workspace per Postmark account creates
  # this. Subsequent workspaces sharing the same account set
  # provisionDomain=false because Postmark domains are account-scoped.
  for_each = var.provisionDomain ? toset([var.domain]) : toset([])

  name = each.key
}

resource "aws_ssm_parameter" "postmark_server_key" {
  name        = "/postmark_app_server/${random_pet.server_suffix.id}/server_key"
  description = "Postmark server API key for ${postmark_server.server.name}"
  type        = "SecureString"
  value       = postmark_server.server.apitokens[0]
}
