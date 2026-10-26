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

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "firewall_type" {
  description = "Firewall type (ew or ns)"
  type        = string
  validation {
    condition     = contains(["ew", "ns"], var.firewall_type)
    error_message = "firewall_type must be either 'ew' or 'ns'"
  }
}

variable "networks" {
  description = "List of network names to attach (e.g., [mngt, trust] or [mngt, trust, untrust])"
  type        = list(string)
}

variable "machine_type" {
  description = "Machine type for firewall instances"
  type        = string
}

variable "firewall_image" {
  description = "Firewall image to use"
  type        = string
}

variable "instances_per_mig" {
  description = "Number of instances per MIG"
  type        = number
}

variable "service_account_email" {
  description = "Service account email for firewall instances"
  type        = string
}

variable "vpcs" {
  description = "Map of VPC IDs by name"
  type        = map(string)
}

variable "subnets" {
  description = "Map of subnet IDs by name"
  type        = map(string)
}

variable "metadata" {
  description = "Metadata to apply to firewall instances"
  type        = map(string)
  default     = {}
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 60
}
