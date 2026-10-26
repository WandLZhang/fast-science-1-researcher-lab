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

# tfdoc:file:description Department folders for research institutions.

# A department is a team folder that sits at var.dept_folder_parent (the org
# root, or the AW folder for a compliance regime) instead of under the Teams
# folder. Each one carries a department=<key> tag, so its admins can get org
# policy authority over their own subtree only.
#
# Service account, bucket, providers file and folder_ids names match the team
# folders of the fast-science-1-researcher-lab fork, so a deployment of that
# fork can move its state here without recreating anything.

locals {
  # Folder-level org policy presets for each department's Development and
  # Production folders. Opt in with dev_org_policies_preset and
  # prod_org_policies_preset.
  edu_org_policy_presets = {
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
  edu_folder_ids = merge(
    { for k, v in module.branch-edu-folder : "team-${k}" => v.id },
    { for k, v in module.branch-edu-dev-folder : "team-${k}-dev" => v.id },
    { for k, v in module.branch-edu-prod-folder : "team-${k}-prod" => v.id }
  )
  edu_providers_raw = {
    for k, v in module.branch-edu-sa : "3-teams-${k}" => {
      bucket = module.branch-edu-gcs[k].name
      name   = "teams"
      sa     = v.email
    }
  }
  edu_service_accounts = {
    for k, v in module.branch-edu-sa : "team-${k}" => v.email
  }
}

module "branch-edu-folder" {
  source   = "../../../modules/folder"
  for_each = var.departments
  parent   = var.dept_folder_parent
  name     = each.value.descriptive_name
  iam = {
    "roles/logging.admin"                  = [module.branch-edu-sa[each.key].iam_email]
    "roles/owner"                          = [module.branch-edu-sa[each.key].iam_email]
    "roles/resourcemanager.folderAdmin"    = [module.branch-edu-sa[each.key].iam_email]
    "roles/resourcemanager.projectCreator" = [module.branch-edu-sa[each.key].iam_email]
    "roles/compute.xpnAdmin"               = [module.branch-edu-sa[each.key].iam_email]
  }
  iam_by_principals = each.value.iam_by_principals
}

module "branch-edu-sa" {
  source       = "../../../modules/iam-service-account"
  for_each     = var.departments
  project_id   = var.automation.project_id
  name         = "prod-teams-${each.key}-0"
  display_name = "Terraform team ${each.key} service account."
  prefix       = var.prefix
  iam = {
    "roles/iam.serviceAccountTokenCreator" = each.value.impersonation_principals
  }
}

module "branch-edu-gcs" {
  source        = "../../../modules/gcs"
  for_each      = var.departments
  project_id    = var.automation.project_id
  name          = "prod-teams-${each.key}-0"
  prefix        = var.prefix
  location      = var.regions.primary
  storage_class = local.gcs_storage_class
  versioning    = true
  iam = {
    "roles/storage.objectAdmin" = [module.branch-edu-sa[each.key].iam_email]
  }
}

# per-department environment folders where project factory SAs can create projects

module "branch-edu-dev-folder" {
  source   = "../../../modules/folder"
  for_each = var.departments
  parent   = module.branch-edu-folder[each.key].id
  name     = "Development"
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
  org_policies = try(local.edu_org_policy_presets[each.value.dev_org_policies_preset], {})
  tag_bindings = null
}

module "branch-edu-prod-folder" {
  source   = "../../../modules/folder"
  for_each = var.departments
  parent   = module.branch-edu-folder[each.key].id
  name     = "Production"
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
  org_policies = try(local.edu_org_policy_presets[each.value.prod_org_policies_preset], {})
  tag_bindings = null
}

# Department tag value under the department tag key from 0-bootstrap. The
# short name is the departments map key (e.g., "engineering").
resource "google_tags_tag_value" "edu_department" {
  for_each    = var.departments
  parent      = var.department_tag.key_id
  short_name  = each.key
  description = "Department tag value for ${each.value.descriptive_name}. Bound to the department's folder; referenced by IAM conditions delegating org-policy admin authority."
}

# Tags inherit, so the Development and Production folders and every project
# under the department folder match the tag too.
resource "google_tags_tag_binding" "edu_department" {
  for_each  = var.departments
  parent    = "//cloudresourcemanager.googleapis.com/${module.branch-edu-folder[each.key].id}"
  tag_value = google_tags_tag_value.edu_department[each.key].id
}

# roles/orgpolicy.policyAdmin can only be granted on the organization. The IAM
# condition limits each grant to resources tagged with that department.
# Pattern from https://cloud.google.com/iam/docs/conditions-overview
resource "google_organization_iam_member" "edu_department_orgpolicy_admin" {
  for_each = merge([
    for k, v in var.departments : {
      for principal in v.department_admin_principals :
      "${k}-${principal}" => {
        dept_key  = k
        principal = principal
      }
    }
  ]...)
  org_id = var.department_tag.org_id
  role   = "roles/orgpolicy.policyAdmin"
  member = each.value.principal
  condition {
    title       = "dept_${each.value.dept_key}_only"
    description = "Restricts orgpolicy.policyAdmin to resources tagged ${var.department_tag.key_short_name}=${each.value.dept_key}."
    expression  = "resource.matchTag(\"${var.department_tag.org_id}/${var.department_tag.key_short_name}\", \"${each.value.dept_key}\")"
  }
}
