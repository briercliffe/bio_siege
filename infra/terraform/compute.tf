resource "google_service_account" "vm" {
  account_id   = "${local.name}-vm"
  display_name = "Bio Siege alpha VM"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "vm" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_artifact_registry_repository_iam_member" "vm_reader" {
  repository = google_artifact_registry_repository.images.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_instance" "server" {
  name                      = "${local.name}-server"
  machine_type              = var.machine_type
  zone                      = var.zone
  tags                      = [local.server_tag]
  allow_stopping_for_update = true
  desired_status            = var.running ? "RUNNING" : "TERMINATED"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  # Postgres data (database = "vm"). The startup script mounts it at /mnt/pgdata.
  dynamic "attached_disk" {
    for_each = google_compute_disk.pgdata
    content {
      source      = attached_disk.value.id
      device_name = "pgdata"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    access_config {
      nat_ip = google_compute_address.server.address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/templates/startup.sh.tftpl", {
      project_id    = var.project_id
      registry      = local.registry
      registry_host = "${var.region}-docker.pkg.dev"
      domain        = var.domain
      acme_email    = var.acme_email
      db_host       = local.db_host
      console_user  = var.console_username
      pgdata_disk   = !local.use_cloudsql
    })
  }

  depends_on = [
    google_secret_manager_secret_iam_member.vm,
    google_sql_user.nakama,
  ]
}
