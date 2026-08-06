output "app_storage" {
  description = "Bucket plików aplikacji - nazwa i region do values charta"

  value = {
    bucket = aws_s3_bucket.app_storage.id
    region = aws_s3_bucket.app_storage.region
  }
}

# Klucz przenosi się do SOPS (wolffire_s3_access_key_id / _secret_access_key)
# raz po apply - potem czytany jest już tylko z SOPS.
output "app_storage_credentials" {
  sensitive   = true
  description = "Klucz IAM wolffire-app do przeniesienia do SOPS"

  value = {
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.app_storage.id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.app_storage.secret
  }
}
