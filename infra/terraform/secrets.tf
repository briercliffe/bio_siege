# Every production secret is generated here and stored in Secret Manager. Nothing is committed.
# The generated values also sit in Terraform state, so the state bucket must stay private (infra/README.md).
#
# Secret ids are fixed: infra/vm/deploy.sh and .github/workflows/alpha.yml read them by name.
locals {
  generated_secrets = {
    "nakama-server-key"             = 32 # socket.server_key. Ships inside the APK, so it is an identifier, not a guard.
    "nakama-http-key"               = 48 # runtime.http_key. The real secret: the worker and admin RPCs use it.
    "nakama-session-encryption-key" = 48
    "nakama-session-refresh-key"    = 48
    "nakama-console-password"       = 32
    "nakama-console-signing-key"    = 48
    "db-password"                   = 32
  }
}

resource "random_password" "secret" {
  for_each = local.generated_secrets
  length   = each.value
  # Alphanumeric only: the values go into URLs (http_key, the database address) unescaped.
  special = false
}

resource "google_secret_manager_secret" "secret" {
  for_each  = local.generated_secrets
  secret_id = each.key
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "secret" {
  for_each    = local.generated_secrets
  secret      = google_secret_manager_secret.secret[each.key].id
  secret_data = random_password.secret[each.key].result
}

# The VM reads every secret when deploy.sh renders its .env.
resource "google_secret_manager_secret_iam_member" "vm" {
  for_each  = local.generated_secrets
  secret_id = google_secret_manager_secret.secret[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

# CI reads only the server key, to bake it into the alpha APK.
resource "google_secret_manager_secret_iam_member" "deployer_server_key" {
  secret_id = google_secret_manager_secret.secret["nakama-server-key"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.deployer.email}"
}
