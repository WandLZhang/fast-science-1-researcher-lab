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
  description = "Identity the function runs as. Holds lienModifier on the Teams folder."
}

output "pubsub_topic" {
  value       = google_pubsub_topic.project_created.id
  description = "Topic that receives CreateProject audit log events from the org sink."
}

output "log_sink_writer_identity" {
  value       = google_logging_organization_sink.create_project.writer_identity
  description = "Org log sink's writer identity (already granted publisher on the topic)."
}
