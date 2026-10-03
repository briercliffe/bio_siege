# Closed alpha hosting (GCP)

Production hosting for the Phase 3 closed alpha (#187). Terraform manages every cloud resource; the alpha
workflow (`.github/workflows/alpha.yml`) builds, checks and deploys. Android only: there is no web alpha.

```
                  one e2-small VM (docker compose)
Android APK --HTTPS/WSS--> Caddy :443 --> Nakama :7350 --> Postgres 16 container (data on its own disk)
                           worker (headless Godot) --'        or Cloud SQL (database = "cloudsql")
                           claims jobs over http_key RPC
```

| Piece | Where |
|---|---|
| VM (e2-small, Debian 12, Docker) | `terraform/compute.tf`, bootstrap `terraform/templates/startup.sh.tftpl` |
| Stack on the VM (Caddy, Nakama, worker, Postgres) | `vm/docker-compose.yml`, `vm/Caddyfile`, `vm/deploy.sh` |
| Database: Postgres data disk with daily snapshots, or Cloud SQL | `terraform/database.tf` |
| VPC, static IP, firewall (443/80 public, 22 from IAP only) | `terraform/network.tf` |
| Secrets (generated, in Secret Manager) | `terraform/secrets.tf` |
| Artifact Registry (`nakama`, `worker` images) | `terraform/main.tf` |
| GitHub Actions access (Workload Identity Federation, no keys) | `terraform/github_oidc.tf` |
| Images | `server/Dockerfile` (+ `server/prod.yml`), `tools/worker/Dockerfile` |
| Alpha flags and APK server settings | `alpha_flags.txt`, `tools/alpha_config.sh` |

## Database modes

| `database` | Data | Backups | Running | Stopped |
|---|---|---|---|---|
| `"vm"` (default) | Postgres 16 container, data on the `bio-siege-pgdata` disk at `/mnt/pgdata` | daily snapshots, 14 days (up to a day of loss) | about $20/mo | about $10/mo |
| `"cloudsql"` | Cloud SQL db-f1-micro, private IP | 14 daily backups and 7 days of point-in-time recovery | about $30/mo | about $11/mo |

The costs are rough estimates. Most of the stopped cost is the reserved static IP, which keeps DNS stable.

The data disk is separate from the boot disk, so recreating the VM keeps the data, and Terraform refuses to
destroy the disk (`prevent_destroy`). Docker waits for the disk mount at boot, and the postgres container
refuses to start if the data directory is missing. It never starts on an empty directory.

## Stopping between sessions

```bash
terraform apply -var running=false   # stop: VM (and Cloud SQL) off; disks, IP and snapshots kept
terraform apply -var running=true    # start: the stack comes back with the last deployed release
```

On boot the startup script re-runs `deploy.sh` with the last release; Caddy keeps its certificate on disk.
While stopped, testers see "Offline". Start the VM before running the alpha workflow (or untick `deploy`).
Keep it running throughout the 2-week gate alpha: D7 retention counts a player only when they are seen on
day 7 itself.

## Bootstrap (once)

Needs a GCP project with billing, `gcloud` (logged in as an owner) and Terraform >= 1.9.

```bash
PROJECT=bio-siege
REGION=us-central1
gcloud storage buckets create "gs://$PROJECT-tfstate" --project="$PROJECT" --location="$REGION" \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://$PROJECT-tfstate" --versioning
# Terraform enables every other API through these two.
gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project="$PROJECT"
```

The state holds the generated secrets, so keep that bucket private to project owners.

## Apply

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # set project_id, domain, acme_email
terraform init -backend-config="bucket=$PROJECT-tfstate"
terraform plan
terraform apply
```

If init fails with `UserProjectAccountProblem` / "billing account not in good standing", your Application
Default Credentials bill API calls to another project. Fix it with `export GOOGLE_CLOUD_QUOTA_PROJECT=bio-siege` for the
shell, or permanently with `gcloud auth application-default set-quota-project bio-siege`.

The first apply takes a few minutes with `database = "vm"`, or 10 to 15 with `"cloudsql"`.

Then:

1. **DNS:** with `dns_zone` set (a Cloud DNS zone in this project), Terraform creates the A record itself.
   Otherwise, create an A record for `domain` pointing at `terraform output -raw server_ip`. Caddy requests the
   certificate on the first deploy, so the record must resolve by then.
2. **GitHub variables:**
   ```bash
   terraform output -json github_variables | python -c "import json,sys; [print(k, v) for k, v in json.load(sys.stdin).items()]" |
     while read -r k v; do gh variable set "$k" --body "$v"; done
   ```
3. **Release keystore** (keep it and its password safe: every alpha update must be signed with it):
   ```bash
   keytool -genkeypair -v -keystore bio_siege_release.keystore -alias bio_siege -keyalg RSA -keysize 2048 -validity 10000
   gh secret set ANDROID_RELEASE_KEYSTORE_BASE64 < <(base64 -w0 bio_siege_release.keystore)
   gh secret set ANDROID_RELEASE_KEYSTORE_USER --body bio_siege
   gh secret set ANDROID_RELEASE_KEYSTORE_PASSWORD
   ```
   In PowerShell, replace the first `gh secret set` with:
   ```powershell
   gh secret set ANDROID_RELEASE_KEYSTORE_BASE64 --body ([Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\bio_siege_release.keystore")))
   ```
4. **Optional:** add a required reviewer to the `alpha` GitHub environment so deploys need approval.

## Release

```bash
gh workflow run alpha.yml --ref main
```

The workflow:

1. Applies `alpha_flags.txt` to `data/game_rules.json` in the runner. The repo copy keeps the flags off.
2. Builds the server bundle and both images.
3. Fails unless the server, the worker and the APK report the same content hash.
4. Pushes the images tagged with the commit SHA.
5. Copies `vm/` to the VM over IAP and runs `deploy.sh <sha>`, then calls `/healthcheck`.
6. Exports a release-signed APK with `bio_siege/server/url` / `key` set, uploaded as the
   `bio-siege-alpha-apk` artifact.

A server deploy and an APK must come from the same run: any data change alters the content hash, and clients
on an older hash get `update_required`. Run with `deploy` unticked to build without deploying.

## Operations

```bash
VM=bio-siege-server; ZONE=us-central1-a

# Nakama console at http://127.0.0.1:7351 (user bio_siege_admin)
gcloud secrets versions access latest --secret=nakama-console-password
gcloud compute ssh "$VM" --zone "$ZONE" --tunnel-through-iap -- -N -L 7351:127.0.0.1:7351

# Shell, status, logs (container logs also go to Cloud Logging)
gcloud compute ssh "$VM" --zone "$ZONE" --tunnel-through-iap
sudo docker compose -f /opt/bio_siege/docker-compose.yml ps
sudo docker compose -f /opt/bio_siege/docker-compose.yml logs -f worker

# Gate report for #187 / #188
BIO_SIEGE_SERVER_URL="https://<domain>" BIO_SIEGE_HTTP_KEY="$(gcloud secrets versions access latest --secret=nakama-http-key)" \
  python tools/server_report.py
```

**Rotating a secret:** `terraform apply -replace='random_password.secret["nakama-http-key"]'`, then re-run
`sudo /opt/bio_siege/deploy.sh "$(cat /opt/bio_siege/release)"` on the VM. Rotating `nakama-server-key` also
needs a new APK. The server key ships inside the APK, so it identifies the game rather than protecting it;
`http_key` is the secret that matters. With `database = "vm"`, do not rotate `db-password` this way: Postgres
reads `POSTGRES_PASSWORD` only when it first creates the data directory, so also run
`ALTER USER nakama PASSWORD '...'` in the postgres container.

**Restore a snapshot (`database = "vm"`):** restore into the existing disk, so Terraform's state stays valid.

```bash
gcloud compute snapshots list --filter="sourceDisk~bio-siege-pgdata"
gcloud compute disks create pgdata-restore --zone "$ZONE" --source-snapshot <snapshot>
gcloud compute instances attach-disk "$VM" --zone "$ZONE" --disk pgdata-restore --device-name pgdata-restore
# on the VM:
sudo docker compose -f /opt/bio_siege/docker-compose.yml stop worker nakama postgres
sudo mkdir -p /mnt/restore && sudo mount /dev/disk/by-id/google-pgdata-restore /mnt/restore
sudo rsync -a --delete /mnt/restore/postgres/ /mnt/pgdata/postgres/
sudo umount /mnt/restore
sudo /opt/bio_siege/deploy.sh "$(cat /opt/bio_siege/release)"
# back locally:
gcloud compute instances detach-disk "$VM" --zone "$ZONE" --disk pgdata-restore
gcloud compute disks delete pgdata-restore --zone "$ZONE"
```

**Restore (`database = "cloudsql"`):** 14 daily backups and 7 days of point-in-time recovery (console, or
`gcloud sql backups list --instance=bio-siege-pg`).

**Moving to Cloud SQL (for example for the gate alpha):**

1. On the VM, dump the database:
   `sudo docker compose -f /opt/bio_siege/docker-compose.yml exec -T postgres pg_dump -U nakama -Fc nakama > nakama.dump`
2. Stop the stack.
3. Detach the data disk from Terraform so it is kept as a fallback: `terraform state rm 'google_compute_disk.pgdata[0]'`.
4. Apply with `database = "cloudsql"`.
5. Re-run the startup script on the VM (`sudo google_metadata_script_runner startup`). It writes the new `DB_HOST`.
6. Load the dump into Cloud SQL with `pg_restore` from a `postgres:16-alpine` container, using `-h <db_host> -U nakama -d nakama`.
7. Run `deploy.sh`.

**Teardown:** the data disk has `prevent_destroy`, and Cloud SQL has deletion protection. Remove both (or
`terraform state rm` the disk to keep it), apply, then run `terraform destroy`.
