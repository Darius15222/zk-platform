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
