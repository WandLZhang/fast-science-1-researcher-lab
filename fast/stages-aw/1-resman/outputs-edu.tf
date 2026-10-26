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

output "departments" {
  description = "Department folders, with their state bucket and service account."
  value = {
    for k, v in module.branch-edu-folder : k => {
      folder          = v.id
      dev_folder      = module.branch-edu-dev-folder[k].id
      prod_folder     = module.branch-edu-prod-folder[k].id
      gcs_bucket      = module.branch-edu-gcs[k].name
      service_account = module.branch-edu-sa[k].email
      tag_value       = google_tags_tag_value.edu_department[k].id
    }
  }
}
