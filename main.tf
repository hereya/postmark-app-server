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
  name = var.domain
}

resource "aws_ssm_parameter" "postmark_server_key" {
  name        = "/postmark_app_server/${random_pet.server_suffix.id}/server_key"
  description = "Postmark server API key for ${postmark_server.server.name}"
  type        = "SecureString"
  value       = postmark_server.server.apitokens[0]
}
