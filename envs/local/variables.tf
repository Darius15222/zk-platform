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
  default     = "ghcr.io/darius15222/zk-auth@sha256:a8588c83db00ff49ca7ad30b7c327f7b638a7fd80eba183cfd61a19626af1c52"

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
