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

# tfdoc:file:description Palo Alto NGFW bootstrap bucket and rendered config
# artifacts (bootstrap.xml + init-cfg.txt) consumed by the VM-Series instances
# via the vmseries-bootstrap-gce-storagebucket metadata key. All resources
# gated on local.paloalto_enabled.

locals {
  # Standard GCP health-check and IAP source ranges, used by the bootstrap.xml
  # management-profile permitted-ip list (matches what cidrs.yaml provides in
  # the reference 2-networking-b ngfw stage).
  pa_healthcheck_cidrs = ["35.191.0.0/16", "130.211.0.0/22"]
  pa_iap_cidrs         = ["35.235.240.0/20"]
}

# Random plaintext password for the bootstrap.xml admin user (hashed by
# openssl-helper.sh via the external data source).
resource "random_password" "paloalto_password" {
  count            = local.paloalto_enabled ? 1 : 0
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Salt used with the password hash (algo 5 / SHA-256 crypt).
resource "random_password" "paloalto_salt" {
  count   = local.paloalto_enabled ? 1 : 0
  length  = 8
  special = false
}

# Shell out to openssl to produce the crypt(3) hash that PAN-OS expects for
# <phash>. The helper script reads {algo, salt, plaintext} from stdin and
# returns {"hash": "..."}.
data "external" "paloalto_openssl" {
  count   = local.paloalto_enabled ? 1 : 0
  program = ["bash", "${path.module}/openssl-helper.sh"]
  query = {
    algo      = "5"
    salt      = random_password.paloalto_salt[0].result
    plaintext = random_password.paloalto_password[0].result
  }
}

# SSH keypair injected into the admin user public-key in bootstrap.xml.
resource "tls_private_key" "paloalto_ssh" {
  count     = local.paloalto_enabled ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Bootstrap bucket. The VM-Series VMs read config/, content/, software/ and
# license/ from this bucket on first boot via vmseries-bootstrap-gce-storagebucket.
module "paloalto_bootstrap_bucket" {
  count         = local.paloalto_enabled ? 1 : 0
  source        = "../../../modules-v54/gcs"
  project_id    = local.pa_project_id
  prefix        = var.prefix
  name          = "paloalto-bootstrap-${local.pa_region}"
  location      = upper(local.pa_region)
  storage_class = "REGIONAL"
  force_destroy = true
}

# Required bootstrap folder placeholders.
resource "google_storage_bucket_object" "paloalto_config_folder" {
  count   = local.paloalto_enabled ? 1 : 0
  name    = "config/"
  bucket  = module.paloalto_bootstrap_bucket[0].name
  content = " "
}

resource "google_storage_bucket_object" "paloalto_content_folder" {
  count   = local.paloalto_enabled ? 1 : 0
  name    = "content/"
  bucket  = module.paloalto_bootstrap_bucket[0].name
  content = " "
}

resource "google_storage_bucket_object" "paloalto_software_folder" {
  count   = local.paloalto_enabled ? 1 : 0
  name    = "software/"
  bucket  = module.paloalto_bootstrap_bucket[0].name
  content = " "
}

resource "google_storage_bucket_object" "paloalto_license_folder" {
  count   = local.paloalto_enabled ? 1 : 0
  name    = "license/"
  bucket  = module.paloalto_bootstrap_bucket[0].name
  content = " "
}

# Rendered PAN-OS bootstrap.xml.
resource "google_storage_bucket_object" "paloalto_bootstrap_xml" {
  count  = local.paloalto_enabled ? 1 : 0
  name   = "config/bootstrap.xml"
  bucket = module.paloalto_bootstrap_bucket[0].name
  content = templatefile("${path.module}/templates/paloalto-bootstrap.xml.tpl", {
    password_hash     = data.external.paloalto_openssl[0].result.hash
    ssh_pubkey        = tls_private_key.paloalto_ssh[0].public_key_openssh
    healthcheck_cidrs = local.pa_healthcheck_cidrs
    iap_cidrs         = local.pa_iap_cidrs
  })
}

# Rendered PAN-OS init-cfg.txt with Panorama registration directive.
resource "google_storage_bucket_object" "paloalto_init_cfg" {
  count  = local.paloalto_enabled ? 1 : 0
  name   = "config/init-cfg.txt"
  bucket = module.paloalto_bootstrap_bucket[0].name
  content = templatefile("${path.module}/templates/paloalto-init-cfg.txt.tpl", {
    panorama_server = var.paloalto.panorama_server
  })
}

# Allow the firewall service account to read bootstrap objects.
resource "google_storage_bucket_iam_member" "paloalto_bootstrap_reader" {
  count  = local.paloalto_enabled ? 1 : 0
  bucket = module.paloalto_bootstrap_bucket[0].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.paloalto_fw[0].email}"
}
