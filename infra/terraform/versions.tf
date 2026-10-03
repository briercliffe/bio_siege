terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State lives in a GCS bucket created once by hand (see infra/README.md, "Bootstrap").
  # `terraform init -backend-config="bucket=<project>-tfstate"` fills in the bucket.
  backend "gcs" {
    prefix = "bio_siege/alpha"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
