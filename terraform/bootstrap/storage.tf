# ── Bucket na pliki aplikacji (Laravel FILESYSTEM_DISK=s3) ───────────────────
# Osobny od stanu i kopii: inna klasa danych (uploady użytkowników), inna
# tożsamość IAM. Powód użycia S3 zamiast dysku lokalnego: storage/app w podzie
# to emptyDir - ginie z podem, a przy >1 replice php każdy pod widziałby inne
# pliki. Wspólny obiektowy storage rozwiązuje jedno i drugie.

resource "aws_s3_bucket" "app_storage" {
  provider = aws.app_storage
  bucket   = var.app_storage_bucket
}

# Wersjonowanie jako siatka na przypadkowe nadpisanie lub skasowanie uploadu;
# stare wersje sprząta reguła cyklu życia, żeby koszty nie rosły bez końca.
resource "aws_s3_bucket_versioning" "app_storage" {
  provider = aws.app_storage
  bucket   = aws_s3_bucket.app_storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_storage" {
  provider = aws.app_storage
  bucket   = aws_s3_bucket.app_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Pliki serwuje aplikacja (podpisane adresy tymczasowe), nie bucket - publiczny
# dostęp jest zablokowany w całości.
resource "aws_s3_bucket_public_access_block" "app_storage" {
  provider = aws.app_storage
  bucket   = aws_s3_bucket.app_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Livewire przy dysku s3 wysyła pliki bezpośrednio z przeglądarki do bucketa
# (presigned URL) - żądanie idzie z originu aplikacji, więc bez CORS przeglądarka
# je zablokuje i upload w UI po prostu nie działa. Presigned URL nie wymaga
# publicznego dostępu - podpis autoryzuje pojedyncze żądanie, public access
# block zostaje w mocy.
resource "aws_s3_bucket_cors_configuration" "app_storage" {
  provider = aws.app_storage
  bucket   = aws_s3_bucket.app_storage.id

  cors_rule {
    allowed_origins = ["https://wolffire.dev"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "app_storage" {
  provider = aws.app_storage
  bucket   = aws_s3_bucket.app_storage.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Tymczasowe uploady Livewire (przeglądarka -> presigned URL -> livewire-tmp/)
  # są przenoszone do docelowej ścieżki przy zapisie formularza, ale porzucone
  # (użytkownik zamknął kartę) zostają - na S3 Livewire nie sprząta ich
  # niezawodnie. Doba wystarcza z ogromnym zapasem.
  rule {
    id     = "expire-livewire-tmp"
    status = "Enabled"

    filter {
      prefix = "livewire-tmp/"
    }

    expiration {
      days = 1
    }
  }
}

# ── Tożsamość aplikacji: pełne CRUD na plikach, ale tylko w tym buckecie ─────
# W odróżnieniu od tożsamości backupowej aplikacja MA prawo kasować - zarządza
# własnymi plikami (usunięcie załącznika przez użytkownika). Zasięg ogranicza
# bucket, nie akcje.

resource "aws_iam_user" "app_storage" {
  name = "wolffire-app"
}

data "aws_iam_policy_document" "app_storage" {
  statement {
    sid = "ListAppBucket"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.app_storage.arn]
  }

  statement {
    sid = "ManageAppObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.app_storage.arn}/*"]
  }
}

resource "aws_iam_user_policy" "app_storage" {
  name   = "app-storage-access"
  user   = aws_iam_user.app_storage.name
  policy = data.aws_iam_policy_document.app_storage.json
}

resource "aws_iam_access_key" "app_storage" {
  user = aws_iam_user.app_storage.name
}
