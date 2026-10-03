variable "project_id" {
  description = "GCP project that hosts the alpha."
  type        = string
}

variable "region" {
  description = "Region for the VM, Cloud SQL and Artifact Registry."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for the VM."
  type        = string
  default     = "us-central1-a"
}

variable "domain" {
  description = "Public API hostname (e.g. api.example.com). Point an A record at the `server_ip` output; Caddy gets the TLS certificate."
  type        = string
}

variable "dns_zone" {
  description = "Cloud DNS managed zone (in project_id) that holds `domain`. Terraform then creates the A record. Empty: create it by hand."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Contact email for Let's Encrypt expiry notices."
  type        = string
}

variable "github_repository" {
  description = "owner/name of the repo allowed to deploy through Workload Identity Federation."
  type        = string
  default     = "briercliffe/bio_siege"
}

variable "machine_type" {
  description = "VM size. e2-small (2 vCPU burst, 2 GB) runs Nakama, the worker and Caddy for the closed alpha."
  type        = string
  default     = "e2-small"
}

variable "running" {
  description = "false stops the VM (and Cloud SQL, if used) between test sessions. Disks, the IP and snapshots are kept."
  type        = bool
  default     = true
}

variable "database" {
  description = "\"vm\": Postgres in a container on the VM, data on its own disk with daily snapshots (cheapest, stops with the VM). \"cloudsql\": Cloud SQL with point-in-time recovery."
  type        = string
  default     = "vm"
  validation {
    condition     = contains(["vm", "cloudsql"], var.database)
    error_message = "database must be \"vm\" or \"cloudsql\"."
  }
}

variable "db_disk_size_gb" {
  description = "Size of the Postgres data disk when database = \"vm\"."
  type        = number
  default     = 10
}

variable "snapshot_retention_days" {
  description = "Daily snapshots of the Postgres data disk are kept this long (database = \"vm\")."
  type        = number
  default     = 14
}

variable "db_tier" {
  description = "Cloud SQL tier (database = \"cloudsql\"). db-f1-micro allows 25 connections; server/prod.yml caps Nakama below that."
  type        = string
  default     = "db-f1-micro"
}

variable "console_username" {
  description = "Nakama console login (reach it through an IAP tunnel, never publicly)."
  type        = string
  default     = "bio_siege_admin"
}
