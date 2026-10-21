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

output "function_name" {
  value       = google_cloudfunctions2_function.auto_lien.name
  description = "Name of the deployed Cloud Function."
}

output "function_uri" {
  value       = google_cloudfunctions2_function.auto_lien.service_config[0].uri
  description = "Cloud Run URI of the function (Gen 2 functions run on Cloud Run)."
}

output "service_account_email" {
  value       = google_service_account.lien_orchestrator.email
  description = "Identity the function runs as. Holds lienModifier on each department folder."
}

output "pubsub_topic" {
  value       = google_pubsub_topic.project_created.id
  description = "Topic that receives CreateProject audit log events from the org sink."
}

output "log_sink_writer_identity" {
  value       = google_logging_organization_sink.create_project.writer_identity
  description = "Org log sink's writer identity (already granted publisher on the topic)."
}
