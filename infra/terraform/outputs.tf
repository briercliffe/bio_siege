output "server_ip" {
  description = "Create an A record for var.domain pointing here before the first deploy."
  value       = google_compute_address.server.address
}

output "server_url" {
  description = "bio_siege/server/url for the alpha APK (GitHub variable ALPHA_SERVER_URL)."
  value       = "https://${var.domain}"
}

output "vm_name" {
  value = google_compute_instance.server.name
}

output "registry" {
  value = local.registry
}

output "db_host" {
  description = "\"postgres\" (container on the VM) or the Cloud SQL private IP."
  value       = local.db_host
}

output "wif_provider" {
  description = "GitHub variable GCP_WIF_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  description = "GitHub variable GCP_DEPLOY_SA."
  value       = google_service_account.deployer.email
}

output "github_variables" {
  description = "Paste into `gh variable set` (see infra/README.md)."
  value = {
    GCP_PROJECT_ID   = var.project_id
    GCP_REGION       = var.region
    GCP_ZONE         = var.zone
    GCP_WIF_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_DEPLOY_SA    = google_service_account.deployer.email
    GCP_VM_NAME      = google_compute_instance.server.name
    GCP_REGISTRY     = local.registry
    ALPHA_SERVER_URL = "https://${var.domain}"
  }
}
