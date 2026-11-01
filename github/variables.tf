variable "owner" {
  description = "GitHub user or organization that owns the lab repositories"
  type        = string
}

variable "visibility" {
  description = "public or private; rulesets on private repos need GitHub Pro or an organization plan"
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private"], var.visibility)
    error_message = "visibility must be public or private"
  }
}
