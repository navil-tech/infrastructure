output "elastic_ip" {
  description = "Public IP of the host, goes into the A record in Wix"
  value       = aws_eip.web.public_ip
}

output "ecr_repository_url" {
  description = "Image repository for the marketing website"
  value       = aws_ecr_repository.marketing_website.repository_url
}

output "ci_role_arn" {
  description = "Role assumed by GitHub Actions through OIDC"
  value       = aws_iam_role.ci.arn
}
