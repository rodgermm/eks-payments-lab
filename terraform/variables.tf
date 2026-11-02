variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "EKS cluster name (also used for Karpenter discovery tags)"
  type        = string
  default     = "eks-payments-lab"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "github_repo" {
  description = "GitHub repo allowed to push images via OIDC, e.g. rodger/eks-payments-lab"
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.1.1"
}
