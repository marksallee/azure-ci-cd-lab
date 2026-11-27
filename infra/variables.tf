variable "environment" {
  type        = string
  description = "dev | staging | prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "app_name" {
  type        = string
  description = "Short app name used in resource names."
  default     = "cicdlab"
}

variable "image" {
  type        = string
  description = "Fully qualified image reference, ideally pinned by digest (ghcr.io/owner/repo@sha256:...)."
  # Placeholder so `terraform destroy` works without knowing the real image.
  default = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "app_version" {
  type        = string
  description = "Git SHA of the build; surfaced by the app at /version."
  default     = "unset"
}

variable "min_replicas" {
  type    = number
  default = 0
}

variable "max_replicas" {
  type    = number
  default = 2
}

variable "log_daily_quota_gb" {
  type        = number
  description = "Hard daily ingestion cap on Log Analytics - a cost guardrail for the lab."
  default     = 0.1
}
