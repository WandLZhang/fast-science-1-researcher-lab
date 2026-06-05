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

# tfdoc:file:description Palo Alto NGFW firewall rules on the mngt / trust /
# untrust VPCs, targeting the firewall service account. All resources gated
# on local.paloalto_enabled.

locals {
  pa_health_check_cidrs = ["35.191.0.0/16", "130.211.0.0/22"]
  pa_iap_ssh_cidrs      = ["35.235.240.0/20"]
  # Resolve VPC names from the ctx_vpcs map. net-vpc-firewall takes a VPC
  # name (per net-vpc-factory wiring at modules-v54/net-vpc-factory/main.tf
  # which passes `network = each.value.name`).
  pa_vpc_names = local.paloalto_enabled ? {
    for k in ["mngt", "trust", "untrust"] :
    k => try(local.ctx_vpcs.names[k], null)
  } : {}
}

module "paloalto_firewall_mngt" {
  count                = local.paloalto_enabled ? 1 : 0
  source               = "../../../modules-v54/net-vpc-firewall"
  project_id           = local.pa_project_id
  network              = local.pa_vpc_names["mngt"]
  default_rules_config = { disabled = true }
  ingress_rules = {
    "allow-iap-ssh" = {
      description          = "Allow IAP SSH/HTTPS to the firewall management interface."
      source_ranges        = local.pa_iap_ssh_cidrs
      targets              = [google_service_account.paloalto_fw[0].email]
      use_service_accounts = true
      rules = [
        { protocol = "tcp", ports = ["22", "443"] }
      ]
    }
    "allow-health-checkers" = {
      description          = "Allow GCP load-balancer health checkers to reach the firewall."
      source_ranges        = local.pa_health_check_cidrs
      targets              = [google_service_account.paloalto_fw[0].email]
      use_service_accounts = true
      rules = [
        { protocol = "tcp", ports = ["22"] }
      ]
    }
    "allow-panorama" = {
      description          = "Allow Panorama management traffic from the configured Panorama server."
      source_ranges        = ["${var.paloalto.panorama_server}/32"]
      targets              = [google_service_account.paloalto_fw[0].email]
      use_service_accounts = true
      rules = [
        { protocol = "tcp", ports = ["3978", "28443"] }
      ]
    }
  }
}

module "paloalto_firewall_trust" {
  count                = local.paloalto_enabled ? 1 : 0
  source               = "../../../modules-v54/net-vpc-firewall"
  project_id           = local.pa_project_id
  network              = local.pa_vpc_names["trust"]
  default_rules_config = { disabled = true }
  ingress_rules = {
    "allow-health-checkers" = {
      description          = "Allow GCP load-balancer health checkers to reach the firewall trust interface."
      source_ranges        = local.pa_health_check_cidrs
      targets              = [google_service_account.paloalto_fw[0].email]
      use_service_accounts = true
      rules = [
        { protocol = "tcp", ports = ["22"] }
      ]
    }
    "allow-iap-ssh" = {
      description          = "Allow IAP SSH to the firewall trust interface for troubleshooting."
      source_ranges        = local.pa_iap_ssh_cidrs
      targets              = [google_service_account.paloalto_fw[0].email]
      use_service_accounts = true
      rules = [
        { protocol = "tcp", ports = ["22"] }
      ]
    }
    "allow-onprem" = {
      description          = "Allow SSH and ICMP from on-prem ranges through the trust VPC."
      source_ranges        = [var.paloalto.onprem_cidr]
      targets              = [google_service_account.paloalto_fw[0].email]
      use_service_accounts = true
      rules = [
        { protocol = "tcp", ports = ["22"] },
        { protocol = "icmp" }
      ]
    }
  }
}

module "paloalto_firewall_untrust" {
  count                = local.paloalto_enabled ? 1 : 0
  source               = "../../../modules-v54/net-vpc-firewall"
  project_id           = local.pa_project_id
  network              = local.pa_vpc_names["untrust"]
  default_rules_config = { disabled = true }
  ingress_rules = {
    "allow-health-checkers" = {
      description          = "Allow GCP load-balancer health checkers to reach the firewall untrust interface."
      source_ranges        = local.pa_health_check_cidrs
      targets              = [google_service_account.paloalto_fw[0].email]
      use_service_accounts = true
      rules = [
        { protocol = "tcp", ports = ["22"] }
      ]
    }
  }
}
