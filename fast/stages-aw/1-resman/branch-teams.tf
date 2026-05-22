/**
 * Copyright 2024 Google LLC
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

# tfdoc:file:description Team stage resources.

locals {
  # Folder-level org policy presets applied to per-team Development and
  # Production folders. Use dev_org_policies_preset / prod_org_policies_preset
  # on each var.team_folders.<team> entry to opt in.
  #
  # PIs and team admins retain orgpolicy.policyAdmin on the team folder via
  # iam_by_principals (which compiles to non-authoritative
  # google_folder_iam_member resources), so per-project overrides remain
  # possible — addresses MSU L1 Issue #1 part 3.
  folder_org_policy_presets = {
    sandbox = {
      "compute.vmExternalIpAccess"         = { rules = [{ allow = { all = true } }] }
      "compute.requireOsLogin"             = { rules = [{ enforce = false }] }
      "compute.skipDefaultNetworkCreation" = { rules = [{ enforce = false }] }
      "gcp.restrictServiceUsage"           = { rules = [{ allow = { all = true } }] }
    }
    hardened = {
      "compute.vmExternalIpAccess"           = { rules = [{ deny = { all = true } }] }
      "compute.requireOsLogin"               = { rules = [{ enforce = true }] }
      "compute.skipDefaultNetworkCreation"   = { rules = [{ enforce = true }] }
      "compute.disableSerialPortAccess"      = { rules = [{ enforce = true }] }
      "iam.disableServiceAccountKeyCreation" = { rules = [{ enforce = true }] }
    }
  }
}

# REMOVED: module "branch-teams-folder" (the "Teams/" wrapper).
# Team folders now nest directly under var.assured_workloads.folder, which
# L0 resolves to either the organization root (COMPLIANCE_REGIME_UNSPECIFIED)
# or the AW workload folder (compliance regime). Schools end up as siblings
# to the L0 bootstrap projects, not buried under a "Teams/" intermediate.
#
# Backwards-compat migration: forget the old Teams folder from state; the
# empty folder is left in GCP for manual cleanup via:
#   gcloud resource-manager folders delete <TEAMS_FOLDER_ID>
removed {
  from = module.branch-teams-folder
  lifecycle {
    destroy = false
  }
}

# REMOVED: module "branch-teams-sa" and module "branch-teams-gcs" — these
# were a separate-stage automation SA + state bucket meant to manage the now-
# deleted Teams wrapper folder. Fast Science manages team folders in this
# resman stage directly, so they had no remaining purpose. Per-team SAs and
# state buckets (branch-teams-team-sa / -gcs) are kept.
removed {
  from = module.branch-teams-sa
  lifecycle {
    destroy = true
  }
}
removed {
  from = module.branch-teams-gcs
  lifecycle {
    destroy = true
  }
}


module "branch-teams-team-folder" {
  source   = "../../../modules/folder"
  for_each = var.fast_features.teams ? coalesce(var.team_folders, {}) : {}
  # parent: var.dept_folder_parent — for unspecified regime, this is the
  # ORG ROOT (department folders sit as siblings to it-services). For
  # compliance, it's the AW workload folder (so departments inherit the
  # regime). Different from var.assured_workloads.folder which always
  # points at where IT stuff lives.
  parent = var.dept_folder_parent
  name   = each.value.descriptive_name
  iam = {
    "roles/logging.admin"                  = [module.branch-teams-team-sa[each.key].iam_email]
    "roles/owner"                          = [module.branch-teams-team-sa[each.key].iam_email]
    "roles/resourcemanager.folderAdmin"    = [module.branch-teams-team-sa[each.key].iam_email]
    "roles/resourcemanager.projectCreator" = [module.branch-teams-team-sa[each.key].iam_email]
    "roles/compute.xpnAdmin"               = [module.branch-teams-team-sa[each.key].iam_email]
  }
  iam_by_principals = each.value.iam_by_principals == null ? {} : each.value.iam_by_principals
}


module "branch-teams-team-sa" {
  source       = "../../../modules/iam-service-account"
  for_each     = var.fast_features.teams ? coalesce(var.team_folders, {}) : {}
  project_id   = var.automation.project_id
  name         = "prod-teams-${each.key}-0"
  display_name = "Terraform team ${each.key} service account."
  prefix       = var.prefix
  iam = {
    "roles/iam.serviceAccountTokenCreator" = concat(
      compact([try(module.branch-teams-team-sa-cicd[each.key].iam_email, null)]),
      (
        each.value.impersonation_principals == null
        ? []
        : [for g in each.value.impersonation_principals : g]
      )
    )
  }
}

module "branch-teams-team-gcs" {
  source        = "../../../modules/gcs"
  for_each      = var.fast_features.teams ? coalesce(var.team_folders, {}) : {}
  project_id    = var.automation.project_id
  name          = "prod-teams-${each.key}-0"
  prefix        = var.prefix
  location      = var.regions.primary
  storage_class = local.gcs_storage_class
  versioning    = true
  iam = {
    "roles/storage.objectAdmin" = [module.branch-teams-team-sa[each.key].iam_email]
  }
}

# per-team environment folders where project factory SAs can create projects

module "branch-teams-team-dev-folder" {
  source   = "../../../modules/folder"
  for_each = var.fast_features.teams ? coalesce(var.team_folders, {}) : {}
  parent   = module.branch-teams-team-folder[each.key].id
  # naming: environment descriptive name
  name = "Development"
  # environment-wide human permissions on the whole teams environment
  iam_by_principals = {}
  iam = {
    (local.custom_roles.service_project_network_admin) = (
      local.branch_optional_sa_lists.pf-dev
    )
    # remove owner here and at project level if SA does not manage project resources
    "roles/owner"                                = local.branch_optional_sa_lists.pf-dev
    "roles/logging.admin"                        = local.branch_optional_sa_lists.pf-dev
    "roles/resourcemanager.folderAdmin"          = local.branch_optional_sa_lists.pf-dev
    "roles/resourcemanager.projectCreator"       = local.branch_optional_sa_lists.pf-dev
    "roles/viewer"                               = local.branch_optional_r_sa_lists.pf-dev
    (var.custom_roles.organization_admin_viewer) = local.branch_optional_r_sa_lists.pf-dev
  }
  org_policies = try(local.folder_org_policy_presets[each.value.dev_org_policies_preset], {})
  tag_bindings = null
}

module "branch-teams-team-prod-folder" {
  source   = "../../../modules/folder"
  for_each = var.fast_features.teams ? coalesce(var.team_folders, {}) : {}
  parent   = module.branch-teams-team-folder[each.key].id
  # naming: environment descriptive name
  name = "Production"
  # environment-wide human permissions on the whole teams environment
  iam_by_principals = {}
  iam = {
    (local.custom_roles.service_project_network_admin) = (
      local.branch_optional_sa_lists.pf-prod
    )
    # remove owner here and at project level if SA does not manage project resources
    "roles/owner"                                = local.branch_optional_sa_lists.pf-prod
    "roles/logging.admin"                        = local.branch_optional_sa_lists.pf-prod
    "roles/resourcemanager.folderAdmin"          = local.branch_optional_sa_lists.pf-prod
    "roles/resourcemanager.projectCreator"       = local.branch_optional_sa_lists.pf-prod
    "roles/viewer"                               = local.branch_optional_r_sa_lists.pf-prod
    (var.custom_roles.organization_admin_viewer) = local.branch_optional_r_sa_lists.pf-prod
  }
  org_policies = try(local.folder_org_policy_presets[each.value.prod_org_policies_preset], {})
  tag_bindings = null
}

# Per-department tag value under L0's department tag key. Tag value short
# name = the team_folders map key (e.g., "engineering"). Used by the
# conditional IAM binding below to scope orgpolicy.policyAdmin to this
# department's folder subtree only.
resource "google_tags_tag_value" "department" {
  for_each    = var.fast_features.teams ? coalesce(var.team_folders, {}) : {}
  parent      = var.department_tag.key_id
  short_name  = each.key
  description = "Department tag value for ${each.value.descriptive_name}. Bound to the department's folder; referenced by IAM conditions delegating org-policy admin authority."
}

# Bind the tag value to the department folder. Tag inheritance means all
# resources nested inside the folder (Development, Production, projects)
# also match the tag, so the IAM condition below covers the whole subtree.
resource "google_tags_tag_binding" "department" {
  for_each  = var.fast_features.teams ? coalesce(var.team_folders, {}) : {}
  parent    = "//cloudresourcemanager.googleapis.com/${module.branch-teams-team-folder[each.key].id}"
  tag_value = google_tags_tag_value.department[each.key].id
}

# Conditional org-level grant of roles/orgpolicy.policyAdmin to the
# department's admin principals, scoped by IAM condition matching the
# department's tag. The role itself is org-scope-only (predefined role
# cannot be granted at folder level, and the underlying orgpolicy.*
# write permissions cannot be put in custom roles — verified empirically
# 2026-05-22), but the IAM condition resource.matchTag(...) restricts the
# effective grant to resources tagged with this department's tag value.
# Pattern from https://cloud.google.com/iam/docs/conditions-overview
resource "google_organization_iam_member" "dept_orgpolicy_admin" {
  for_each = var.fast_features.teams ? merge([
    for k, v in coalesce(var.team_folders, {}) : {
      for principal in v.department_admin_principals :
      "${k}-${principal}" => {
        dept_key  = k
        principal = principal
      }
    }
  ]...) : {}

  org_id = var.department_tag.org_id
  role   = "roles/orgpolicy.policyAdmin"
  member = each.value.principal
  condition {
    title       = "dept_${each.value.dept_key}_only"
    description = "Restricts orgpolicy.policyAdmin to resources tagged ${var.department_tag.key_short_name}=${each.value.dept_key}."
    expression  = "resource.matchTag(\"${var.department_tag.org_id}/${var.department_tag.key_short_name}\", \"${each.value.dept_key}\")"
  }
}
