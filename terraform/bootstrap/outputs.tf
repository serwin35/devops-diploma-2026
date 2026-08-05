# Klucze odczytujemy raz, po `apply`, i przenosimy do secrets.sops.yaml:
#
#   terraform -chdir=terraform/bootstrap output -json credentials | jq
#
# Potem już nie są potrzebne - ale zostają w stanie lokalnym, dlatego
# terraform/bootstrap/terraform.tfstate jest w .gitignore.
output "credentials" {
  sensitive   = true
  description = "Klucze IAM do przeniesienia do SOPS"

  value = {
    tf_state = {
      AWS_ACCESS_KEY_ID     = aws_iam_access_key.tf_state.id
      AWS_SECRET_ACCESS_KEY = aws_iam_access_key.tf_state.secret
    }
    jenkins_backup = {
      AWS_ACCESS_KEY_ID     = aws_iam_access_key.jenkins_backup.id
      AWS_SECRET_ACCESS_KEY = aws_iam_access_key.jenkins_backup.secret
    }
    alertmanager = {
      AWS_ACCESS_KEY_ID     = aws_iam_access_key.alertmanager.id
      AWS_SECRET_ACCESS_KEY = aws_iam_access_key.alertmanager.secret
    }
  }
}

output "alerts_sns_topic_arn" {
  description = "ARN tematu SNS dla alertmanager.yml (sns_configs)"
  value       = aws_sns_topic.alerts.arn
}

output "buckets" {
  description = "Utworzone buckety"

  value = {
    state = {
      name   = aws_s3_bucket.state.id
      region = var.state_region
    }
    backups = {
      name   = aws_s3_bucket.backups.id
      region = var.backups_region
    }
  }
}
