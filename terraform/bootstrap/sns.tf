# Kanał e-mail dla alertów: Alertmanager publikuje do SNS (natywne
# sns_configs), a subskrypcja e-mail dostarcza wiadomość. Wybór SNS zamiast
# własnego MTA albo SES: zero walki z reputacją IP i filtrami spamu, a
# jedyna "infrastruktura" to topic + subskrypcja, obie w Terraformie.
#
# Subskrypcja e-mail wymaga JEDNORAZOWEGO potwierdzenia: AWS wysyła link
# "Confirm subscription" na podany adres. Do czasu kliknięcia stan subskrypcji
# to PendingConfirmation i alerty nie wychodzą.

resource "aws_sns_topic" "alerts" {
  name = "wolffire-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alerts_email
}

# Osobna tożsamość tylko do publikacji alertów - kompromitacja klucza z
# maszyny monitoringu nie daje dostępu ani do stanu, ani do kopii zapasowych.
resource "aws_iam_user" "alertmanager" {
  name = "wolffire-alertmanager"
}

data "aws_iam_policy_document" "alertmanager" {
  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_user_policy" "alertmanager" {
  name   = "sns-publish-only"
  user   = aws_iam_user.alertmanager.name
  policy = data.aws_iam_policy_document.alertmanager.json
}

resource "aws_iam_access_key" "alertmanager" {
  user = aws_iam_user.alertmanager.name
}
