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
  description = "Project where the auto-lien Cloud Function and Pub/Sub topic live. Typically the L0 automation project (<PREFIX>-prod-iac-core-0)."
  type        = string
}

variable "region" {
  description = "Region for the Cloud Function and source bucket."
  type        = string
  default     = "us-central1"
}

variable "organization_id" {
  description = "GCP organization numeric ID. Used for the aggregated log sink that captures CreateProject events org-wide."
  type        = string
}

variable "department_folder_ids" {
  description = "Department folder IDs from 1-resman (the folder attribute of each entry in `terraform output departments`). Numeric IDs or folders/NNN. Only projects under these folders get auto-liens."
  type        = list(string)
  validation {
    condition     = length(var.department_folder_ids) > 0
    error_message = "List at least one department folder."
  }
}

variable "lien_reason" {
  description = "Human-readable reason stored on every lien created by the function. Should tell a user how to request lien removal (e.g., who to contact)."
  type        = string
  default     = "Auto-applied lien on delegated research project. Contact IT to remove."
}
