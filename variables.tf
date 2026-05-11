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
