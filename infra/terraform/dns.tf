# A record for the API hostname, when its zone is in Cloud DNS in this project (var.dns_zone).
data "google_dns_managed_zone" "api" {
  count = var.dns_zone == "" ? 0 : 1
  name  = var.dns_zone
}

resource "google_dns_record_set" "api" {
  count        = var.dns_zone == "" ? 0 : 1
  managed_zone = data.google_dns_managed_zone.api[0].name
  name         = "${var.domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.server.address]

  lifecycle {
    precondition {
      condition     = endswith("${var.domain}.", ".${data.google_dns_managed_zone.api[0].dns_name}")
      error_message = "domain must sit inside the dns_zone's DNS name."
    }
  }
}
