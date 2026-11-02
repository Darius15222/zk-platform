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
  default     = "ghcr.io/darius15222/zk-auth@sha256:c1b5dc6e32cea0e3c7c412a3fcd56f0853d1d1ab86bd339b785ff5fd57fc9d17"

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
