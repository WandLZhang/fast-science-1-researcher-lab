/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 */

# blueprints/research-delegation/auto-lien/main.tf
#
# Org-wide Cloud Function that auto-attaches a deletion lien to every project
# created under the Teams folder subtree. Catches projects created via the
# Console (which bypass the L1 Project Factory and its built-in lien_reason).
#
# Topology:
#   Org-level Aggregated Log Sink  →  Pub/Sub topic (in CF project)
#                                      ↓ Eventarc trigger
#                              Cloud Function (Gen 2 / Cloud Run)
#                                      ↓ liens.create
#                              New project gets a lien
#
# Deploy:
#   terraform init
#   terraform apply
#     -var "project_id=<PREFIX>-prod-iac-core-0"
#     -var "region=us-central1"
#     -var "organization_id=NNNNNNNNNNNN"
#     -var "teams_folder_id=NNNNNNNNNNNN"
#     -var "lien_reason=Research project — contact IT to delete"

terraform {
  required_version = ">= 1.5"
  required_providers {
    google      = { source = "hashicorp/google",      version = ">= 5.30" }
    google-beta = { source = "hashicorp/google-beta", version = ">= 5.30" }
    archive     = { source = "hashicorp/archive",     version = ">= 2.4" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Required APIs in the function's host project
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Service account that runs the Cloud Function and creates liens.
resource "google_service_account" "lien_orchestrator" {
  project      = var.project_id
  account_id   = "auto-lien-orchestrator"
  display_name = "Auto-lien orchestrator (research-delegation blueprint)"
  description  = "Runs the auto-lien Cloud Function. Has lienModifier on the Teams folder."
}

# Lien-modifier on the Teams folder so the SA can create liens on any project
# in the subtree. Cascades to all team subfolders.
resource "google_folder_iam_member" "lien_modifier_on_teams" {
  folder = "folders/${var.teams_folder_id}"
  role   = "roles/resourcemanager.lienModifier"
  member = "serviceAccount:${google_service_account.lien_orchestrator.email}"
}

# Folder Viewer so the SA can read project ancestry to confirm the new project
# really is under the Teams folder before attaching a lien.
resource "google_folder_iam_member" "folder_viewer_on_teams" {
  folder = "folders/${var.teams_folder_id}"
  role   = "roles/resourcemanager.folderViewer"
  member = "serviceAccount:${google_service_account.lien_orchestrator.email}"
}

# Pub/Sub topic that receives CreateProject audit log events from the org sink.
resource "google_pubsub_topic" "project_created" {
  project = var.project_id
  name    = "auto-lien-project-created"
}

# Org-level aggregated log sink. Captures CreateProject events from the entire
# org and routes them to the Pub/Sub topic above. Filter scopes to events
# whose target ancestor includes the Teams folder, so we don't lien projects
# created elsewhere (e.g., Common Services, Networking).
resource "google_logging_organization_sink" "create_project" {
  name             = "auto-lien-create-project"
  org_id           = var.organization_id
  destination      = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.project_created.name}"
  include_children = true

  # CreateProject audit events. We additionally filter by parent in the CF
  # itself because the audit log entry's resource.labels.project_id is the
  # NEW project ID; the parent ancestry check needs an SDK call.
  filter = <<-EOT
    logName:"cloudaudit.googleapis.com%2Factivity"
    AND protoPayload.serviceName="cloudresourcemanager.googleapis.com"
    AND protoPayload.methodName="CreateProject"
    AND operation.last=true
  EOT
}

# Allow the sink's writer identity to publish to the Pub/Sub topic.
resource "google_pubsub_topic_iam_member" "sink_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.project_created.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_organization_sink.create_project.writer_identity
}

# Bundle the function source.
data "archive_file" "function_src" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/.build/function.zip"
}

resource "google_storage_bucket" "function_src" {
  project                     = var.project_id
  name                        = "${var.project_id}-auto-lien-src"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_object" "function_src" {
  name   = "auto-lien-${data.archive_file.function_src.output_md5}.zip"
  bucket = google_storage_bucket.function_src.name
  source = data.archive_file.function_src.output_path
}

# Cloud Function Gen 2 — the actual handler.
resource "google_cloudfunctions2_function" "auto_lien" {
  project  = var.project_id
  name     = "auto-lien"
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "handle_project_created"
    source {
      storage_source {
        bucket = google_storage_bucket.function_src.name
        object = google_storage_bucket_object.function_src.name
      }
    }
  }

  service_config {
    available_memory               = "256Mi"
    timeout_seconds                = 60
    max_instance_count             = 10
    service_account_email          = google_service_account.lien_orchestrator.email
    all_traffic_on_latest_revision = true

    environment_variables = {
      TEAMS_FOLDER_ID = var.teams_folder_id
      LIEN_REASON     = var.lien_reason
      ORG_ID          = var.organization_id
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.project_created.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.lien_orchestrator.email
  }

  depends_on = [google_project_service.apis]
}
