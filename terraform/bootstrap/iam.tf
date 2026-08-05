# Dwie rozdzielone tożsamości zamiast jednego klucza do wszystkiego.
# Kompromitacja tożsamości backupowej nie daje dostępu do stanu i odwrotnie.

# ── Terraform: pełny dostęp do stanu, zero dostępu do kopii ──────────────────

resource "aws_iam_user" "tf_state" {
  name = "wolffire-tf-state"
}

data "aws_iam_policy_document" "tf_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "ManageState"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_user_policy" "tf_state" {
  name   = "state-access"
  user   = aws_iam_user.tf_state.name
  policy = data.aws_iam_policy_document.tf_state.json
}

resource "aws_iam_access_key" "tf_state" {
  user = aws_iam_user.tf_state.name
}

# ── Jenkins: zapis kopii, ale BEZ prawa kasowania ───────────────────────────
#
# To najważniejsza decyzja w tym pliku. Zadanie backupowe nie ma powodu niczego
# usuwać - usuwaniem zajmuje się reguła cyklu życia bucketa. Dzięki temu
# przejęty token Jenkinsa albo błąd w skrypcie nie skasuje kopii zapasowych,
# czyli dokładnie tego, po co one istnieją.

resource "aws_iam_user" "jenkins_backup" {
  name = "wolffire-jenkins-backup"
}

data "aws_iam_policy_document" "jenkins_backup" {
  statement {
    sid       = "ListBackupBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }

  # restic potrzebuje odczytu, żeby wiedzieć, co już wysłał, i zapisu nowych
  # obiektów. Nie potrzebuje DeleteObject na danych kopii.
  statement {
    sid = "WriteBackups"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }

  # Wyjątek od zakazu kasowania: pliki blokad (locks/) to przejściowe znaczniki
  # koordynacji, nie dane kopii. Bez tego restic zostawia po każdym przebiegu
  # martwą blokadę ("error while unlocking" w logu) i kolejne przebiegi w końcu
  # padną na "repository is already locked".
  statement {
    sid       = "DeleteResticLocks"
    actions   = ["s3:DeleteObject"]
    resources = ["${aws_s3_bucket.backups.arn}/locks/*"]
  }

  statement {
    sid           = "DenyDelete"
    effect        = "Deny"
    actions       = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    not_resources = ["${aws_s3_bucket.backups.arn}/locks/*"]
  }
}

resource "aws_iam_user_policy" "jenkins_backup" {
  name   = "backup-write-only"
  user   = aws_iam_user.jenkins_backup.name
  policy = data.aws_iam_policy_document.jenkins_backup.json
}

resource "aws_iam_access_key" "jenkins_backup" {
  user = aws_iam_user.jenkins_backup.name
}
