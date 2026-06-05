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

# tfdoc:file:description Palo Alto NVA appliance variables (active only when
# the selected dataset/tfvars set paloalto.enabled = true).

variable "paloalto" {
  description = "Palo Alto NGFW NVA configuration for the NVA journey path. Leave default for non-paloalto deployments."
  type = object({
    enabled             = optional(bool, false)
    networking_project  = optional(string, "net-prod-0") # short name resolved via ctx_projects
    panorama_server     = optional(string)
    firewall_image      = optional(string, "projects/paloaltonetworksgcp-public/global/images/vmseries-flex-byol-1026")
    machine_type        = optional(string, "n2-standard-4")
    instances_per_mig   = optional(number, 2)
    ssh_public_key_file = optional(string)
    mngt_cidr           = optional(string, "10.75.0.0/24")
    onprem_cidr         = optional(string, "10.0.0.0/8")
  })
  default  = {}
  nullable = false
  validation {
    condition     = !try(var.paloalto.enabled, false) || try(var.paloalto.panorama_server, null) != null
    error_message = "paloalto.panorama_server is required when paloalto.enabled = true."
  }
}

locals {
  paloalto_enabled = try(var.paloalto.enabled, false)
  # Region for Palo resources. This stage has no `var.regions`; the canonical
  # primary region lives in the dataset defaults under context.locations.primary
  # and is exposed via local.ctx.locations.primary.
  pa_region = try(local.ctx.locations.primary, null)
  pa_project_id = local.paloalto_enabled ? lookup(
    local.ctx_projects.project_ids, var.paloalto.networking_project, var.paloalto.networking_project
  ) : null
  pa_vpcs = local.paloalto_enabled ? {
    for k in ["mngt", "trust", "untrust"] : k => try(local.ctx_vpcs.self_links[k], null)
  } : {}
  pa_subnets = local.paloalto_enabled ? {
    for k in ["mngt", "trust", "untrust"] : k => try(local.ctx_vpcs.subnets_by_vpc["${k}/${local.pa_region}/${k}-default"], null)
  } : {}
}
