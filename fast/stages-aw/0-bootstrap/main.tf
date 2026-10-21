/**
 * Copyright 2022 Google LLC
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

locals {
  gcs_storage_class = (
    length(split("-", local.locations.gcs)) < 2
    ? "MULTI_REGIONAL"
    : "REGIONAL"
  )
  principals = {
    for k, v in var.groups : k => (
      can(regex("^[a-zA-Z]+:", v))
      ? v
      : "group:${v}@${var.organization.domain}"
    )
  }
  # Upstream: all locations were hardcoded to var.regions.primary.
  # Changed to use var.locations (defaults to US multi-region for GCS/BQ) so
  # storage/BQ aren't locked to a single region while compute stays in
  # regions.primary. Sentinel defaults ("global" for logging, null for kms)
  # fall back to var.regions.primary so the keyring stays regional (Cloud KMS
  # requires either a region or a lowercase multi-region like "us"/"europe",
  # not the uppercase "US" used by GCS/BQ).
  locations = {
    bq      = var.locations.bq
    gcs     = var.locations.gcs
    logging = var.locations.logging != "global" ? var.locations.logging : var.regions.primary
    pubsub  = length(var.locations.pubsub) > 0 ? var.locations.pubsub : [var.regions.primary]
    kms     = coalesce(var.locations.kms, var.regions.primary)
  }
  # naming: environment used in most resource names
  prefix = join("-", compact([var.prefix, "prod"]))
  # Top-level managed folder name. Used both for the AW workload display
  # name (compliance regimes) and for the regular wrapper folder created at
  # the org root (unspecified regime). Default:
  #   - unspecified regime: "it-services" (IT-group convention)
  #   - compliance regime: regime short code from regime_mapping (e.g., "il5")
  # Override per deployment via var.managed_folder_name.
  managed_folder_name = coalesce(
    var.managed_folder_name,
    var.assured_workloads.regime == "COMPLIANCE_REGIME_UNSPECIFIED"
    ? "it-services"
    : lower(lookup(var.regime_mapping, var.assured_workloads.regime, "managed"))
  )
}
