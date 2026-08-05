locals {
  # Aplikacja Access jest identyfikowana pełną nazwą hosta. Pusta strefa oznacza
  # wpis na domenie apex - wtedy zmienna subdomain zawiera już całą nazwę.
  domain = var.zone != null ? "${var.subdomain}.${var.zone}" : var.subdomain
}
