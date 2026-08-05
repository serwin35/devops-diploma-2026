# ── Bucket na stan Terraforma ────────────────────────────────────────────────
# Oddzielony od kopii zapasowych świadomie: stan zawiera wygenerowane hasła
# i klucze jawnym tekstem, więc ma inną klasę wrażliwości i inne uprawnienia.

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket
}

# Wersjonowanie to jedyna siatka bezpieczeństwa przy uszkodzonym stanie -
# bez niego zły `apply` jest nieodwracalny.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Stare wersje stanu nie mogą rosnąć w nieskończoność, ale muszą żyć na tyle
# długo, żeby dało się cofnąć po nieudanej zmianie.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ── Bucket na kopie zapasowe ─────────────────────────────────────────────────

resource "aws_s3_bucket" "backups" {
  provider = aws.backups
  bucket   = var.backups_bucket
}

resource "aws_s3_bucket_versioning" "backups" {
  provider = aws.backups
  bucket   = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  provider = aws.backups
  bucket   = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  provider = aws.backups
  bucket   = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Kopie schodzą do tańszej klasy po miesiącu - odtwarzamy z nich rzadko,
# a trzymamy długo.
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  provider = aws.backups
  bucket   = aws_s3_bucket.backups.id

  rule {
    id     = "tier-and-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
