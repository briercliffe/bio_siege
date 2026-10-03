resource "google_compute_network" "main" {
  name                    = local.name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "main" {
  name                     = local.name
  network                  = google_compute_network.main.id
  region                   = var.region
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_address" "server" {
  name       = "${local.name}-server"
  region     = var.region
  depends_on = [google_project_service.apis]
}

# Clients reach Caddy on 443 (80 only for the ACME challenge and the HTTPS redirect).
resource "google_compute_firewall" "https" {
  name          = "${local.name}-allow-https"
  network       = google_compute_network.main.id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.server_tag]
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# SSH only through Identity-Aware Proxy (deploys and the Nakama console tunnel). No public SSH.
resource "google_compute_firewall" "iap_ssh" {
  name          = "${local.name}-allow-iap-ssh"
  network       = google_compute_network.main.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.server_tag]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
