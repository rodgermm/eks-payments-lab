output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.payments.repository_url
}

output "github_ci_role_arn" {
  description = "Set as GitHub repo variable AWS_ROLE_ARN"
  value       = aws_iam_role.github_ci.arn
}

output "karpenter_node_role" {
  value = module.karpenter.node_iam_role_name
}
