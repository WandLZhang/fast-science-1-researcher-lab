/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

# tfdoc:file:description Palo Alto NGFW service account, IAM, and E/W and N/S
# managed instance groups. All resources gated on local.paloalto_enabled.

locals {
  pa_metadata = local.paloalto_enabled ? merge(
    {
      vmseries-bootstrap-gce-storagebucket = module.paloalto_bootstrap_bucket[0].name
      mgmt-interface-swap                  = "enable"
    },
    var.paloalto.ssh_public_key_file != null ? {
      ssh-keys = "admin:${file(var.paloalto.ssh_public_key_file)}"
    } : {}
  ) : {}
}

resource "google_service_account" "paloalto_fw" {
  count        = local.paloalto_enabled ? 1 : 0
  project      = local.pa_project_id
  account_id   = "paloalto-firewall-sa"
  display_name = "Palo Alto NGFW firewall instances"
}

resource "google_project_iam_custom_role" "paloalto_fw" {
  count   = local.paloalto_enabled ? 1 : 0
  project = local.pa_project_id
  role_id = "paloalto.firewall"
  title   = "Palo Alto Firewall"
  permissions = [
    "storage.buckets.get",
    "logging.buckets.write",
    "opsconfigmonitoring.resourceMetadata.write",
    "autoscaling.sites.writeMetrics",
    "monitoring.metricDescriptors.create",
    "monitoring.metricDescriptors.get",
    "monitoring.metricDescriptors.list",
    "monitoring.monitoredResourceDescriptors.get",
    "monitoring.monitoredResourceDescriptors.list",
    "monitoring.timeSeries.create",
  ]
}

resource "google_project_iam_member" "paloalto_fw_role" {
  count   = local.paloalto_enabled ? 1 : 0
  project = local.pa_project_id
  role    = google_project_iam_custom_role.paloalto_fw[0].id
  member  = "serviceAccount:${google_service_account.paloalto_fw[0].email}"
}

resource "google_project_iam_member" "paloalto_fw_compute_viewer" {
  count   = local.paloalto_enabled ? 1 : 0
  project = local.pa_project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.paloalto_fw[0].email}"
}

module "ew_firewall" {
  count                 = local.paloalto_enabled ? 1 : 0
  source                = "../../../modules-v54/paloalto-firewall"
  project_id            = local.pa_project_id
  region                = local.pa_region
  firewall_type         = "ew"
  networks              = ["mngt", "trust"]
  machine_type          = var.paloalto.machine_type
  firewall_image        = var.paloalto.firewall_image
  instances_per_mig     = var.paloalto.instances_per_mig
  service_account_email = google_service_account.paloalto_fw[0].email
  vpcs                  = local.pa_vpcs
  subnets               = local.pa_subnets
  metadata              = local.pa_metadata
}

module "ns_firewall" {
  count                 = local.paloalto_enabled ? 1 : 0
  source                = "../../../modules-v54/paloalto-firewall"
  project_id            = local.pa_project_id
  region                = local.pa_region
  firewall_type         = "ns"
  networks              = ["mngt", "trust", "untrust"]
  machine_type          = var.paloalto.machine_type
  firewall_image        = var.paloalto.firewall_image
  instances_per_mig     = var.paloalto.instances_per_mig
  service_account_email = google_service_account.paloalto_fw[0].email
  vpcs                  = local.pa_vpcs
  subnets               = local.pa_subnets
  metadata              = local.pa_metadata
}
