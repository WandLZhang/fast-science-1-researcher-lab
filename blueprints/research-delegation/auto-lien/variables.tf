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

variable "teams_folder_id" {
  description = "Numeric folder ID of the Teams folder created by L0 Stage 1 with fast_features.teams = true. Only projects under this folder will get auto-liens."
  type        = string
}

variable "lien_reason" {
  description = "Human-readable reason stored on every lien created by the function. Should tell a user how to request lien removal (e.g., who to contact)."
  type        = string
  default     = "Auto-applied lien on delegated research project. Contact IT to remove."
}
