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

variable "department_tag" {
  # tfdoc:variable:source 0-bootstrap
  description = "Department tag key from 0-bootstrap. Each departments entry gets a tag value under it."
  type = object({
    key_id         = string
    key_short_name = string
    key_namespaced = string
    org_id         = number
  })
  default = null
}

variable "departments" {
  description = "Department folders for research institutions, created under dept_folder_parent and tagged department=<key>. dev_org_policies_preset and prod_org_policies_preset accept \"sandbox\" or \"hardened\". department_admin_principals get roles/orgpolicy.policyAdmin on the organization, limited by an IAM condition to the department's tagged subtree."
  type = map(object({
    descriptive_name            = string
    iam_by_principals           = optional(map(list(string)), {})
    impersonation_principals    = optional(list(string), [])
    dev_org_policies_preset     = optional(string)
    prod_org_policies_preset    = optional(string)
    department_admin_principals = optional(list(string), [])
  }))
  nullable = false
  default  = {}
  validation {
    condition = alltrue(flatten([
      for k, v in var.departments : [
        for p in [v.dev_org_policies_preset, v.prod_org_policies_preset] :
        contains(["none", "sandbox", "hardened"], coalesce(p, "none"))
      ]
    ]))
    error_message = "Org policy presets must be \"sandbox\" or \"hardened\"."
  }
  validation {
    condition = (
      length(var.departments) == 0 ||
      (var.dept_folder_parent != null && var.department_tag != null)
    )
    error_message = "departments needs dept_folder_parent and department_tag from the 0-bootstrap outputs."
  }
  validation {
    condition = length(setintersection(
      keys(var.departments), keys(coalesce(var.team_folders, {}))
    )) == 0
    error_message = "departments and team_folders can't share keys: both use prod-teams-<key>-0 names."
  }
}

variable "dept_folder_parent" {
  # tfdoc:variable:source 0-bootstrap
  description = "Parent for department folders: the organization for an unspecified regime, the AW folder otherwise."
  type        = string
  default     = null
}
