locals {
  use_cloudsql = var.database == "cloudsql"
  # "postgres" is the compose service name on the VM; deploy.sh starts that service when it sees it.
  db_host = local.use_cloudsql ? google_sql_database_instance.main[0].private_ip_address : "postgres"
}

# --- database = "vm": Postgres container, data on a dedicated persistent disk -------------------------------

resource "google_compute_disk" "pgdata" {
  count = local.use_cloudsql ? 0 : 1
  name  = "${local.name}-pgdata"
  zone  = var.zone
  type  = "pd-balanced"
  size  = var.db_disk_size_gb

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.apis]
}

# Crash-consistent daily snapshots; Postgres recovers from its WAL on restore. Taken whether or not the VM runs.
resource "google_compute_resource_policy" "pgdata_snapshots" {
  count  = local.use_cloudsql ? 0 : 1
  name   = "${local.name}-pgdata-daily"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "03:00"
      }
    }
    retention_policy {
      max_retention_days    = var.snapshot_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    snapshot_properties {
      storage_locations = [var.region]
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_compute_disk_resource_policy_attachment" "pgdata_snapshots" {
  count = local.use_cloudsql ? 0 : 1
  name  = google_compute_resource_policy.pgdata_snapshots[0].name
  disk  = google_compute_disk.pgdata[0].name
  zone  = var.zone
}

# --- database = "cloudsql": managed Postgres on a private IP ------------------------------------------------

# Private services access: Cloud SQL gets a private IP inside the VPC and no public IP.
resource "google_compute_global_address" "private_services" {
  count         = local.use_cloudsql ? 1 : 0
  name          = "${local.name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_services" {
  count                   = local.use_cloudsql ? 1 : 0
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services[0].name]
}

resource "google_sql_database_instance" "main" {
  count               = local.use_cloudsql ? 1 : 0
  name                = "${local.name}-pg"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = true

  settings {
    tier                        = var.db_tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    activation_policy           = var.running ? "ALWAYS" : "NEVER"
    disk_type                   = "PD_SSD"
    disk_size                   = 10
    disk_autoresize             = true
    deletion_protection_enabled = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
      }
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "nakama" {
  count    = local.use_cloudsql ? 1 : 0
  name     = "nakama"
  instance = google_sql_database_instance.main[0].name
}

resource "google_sql_user" "nakama" {
  count    = local.use_cloudsql ? 1 : 0
  name     = "nakama"
  instance = google_sql_database_instance.main[0].name
  password = random_password.secret["db-password"].result
}
