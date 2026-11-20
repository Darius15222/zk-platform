variable "kubeconfig" {
  description = "kubeconfig of the k3d cluster written by local-stack/up.sh"
  type        = string
  default     = "~/.kube/config.zk-lab"
}

variable "domain" {
  description = "local DNS suffix; map <name>.<domain> to 127.0.0.1 in /etc/hosts"
  type        = string
  default     = "zk.local"
}

variable "zk_auth_image" {
  description = "zk-auth image pinned by digest; bumped by PR when zk-auth CI publishes a new one"
  type        = string
  default     = "ghcr.io/darius15222/zk-auth@sha256:28b5cdae29ba9c1b73bcde1220702cee67fc4c86b6f9d10208eafe3bf29845f3"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.zk_auth_image))
    error_message = "zk_auth_image must be pinned by digest"
  }
}

variable "detections_dir" {
  description = "path to a zk-detections checkout; empty = the sibling folder in the workspace"
  type        = string
  default     = ""
}
