# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Auto-lien Cloud Function.

Triggered on every CreateProject audit log event published to the Pub/Sub
topic by the org-level aggregated log sink. For each new project that lives
under one of the configured department folders, attaches a deletion lien.

The lien blocks resourcemanager.projects.delete until removed by an identity
holding roles/resourcemanager.lienModifier on the project (or this function's
SA, since it has lienModifier on each department folder).

Environment variables (set by Terraform):
    DEPARTMENT_FOLDER_IDS  Comma-separated department folder IDs. Projects
                           under any of them qualify for auto-lien.
    LIEN_REASON            Reason text stored on the lien.
    ORG_ID                 Org ID — used as a sanity-check upper bound when
                           walking a project's ancestry.
"""

from __future__ import annotations

import base64
import json
import logging
import os
from typing import Iterable

from cloudevents.http import CloudEvent
import functions_framework
from google.cloud import resourcemanager_v3

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

DEPARTMENT_FOLDERS = frozenset(
    f"folders/{folder_id.strip()}"
    for folder_id in os.environ["DEPARTMENT_FOLDER_IDS"].split(",")
    if folder_id.strip()
)
LIEN_REASON = os.environ["LIEN_REASON"]
ORG_ID = os.environ["ORG_ID"]
LIEN_RESTRICTIONS = ["resourcemanager.projects.delete"]
LIEN_ORIGIN = "auto-lien-cloud-function"


def _decode_pubsub(event: CloudEvent) -> dict:
    """Pub/Sub Eventarc events wrap the message in event.data['message']['data']
    (base64). The decoded body is the audit log entry as JSON."""
    msg = event.data["message"]
    if "data" not in msg:
        raise ValueError("pubsub message has no data field")
    return json.loads(base64.b64decode(msg["data"]).decode("utf-8"))


def _project_id_from_audit(entry: dict) -> str | None:
    """CreateProject audit log puts the new project ID in
    protoPayload.request.project.projectId once the operation completes
    (operation.last == true). Fall back to resourceName parsing."""
    payload = entry.get("protoPayload", {})
    project_id = payload.get("request", {}).get("project", {}).get(
        "projectId"
    ) or payload.get("response", {}).get("projectId")
    if project_id:
        return project_id
    rn = payload.get("resourceName", "")
    if rn.startswith("projects/"):
        return rn.split("/", 1)[1]
    return None


def _ancestors(project_id: str) -> Iterable[str]:
    """Yield ancestor resource names of a project, e.g.
    ['projects/123', 'folders/456', 'folders/789', 'organizations/999']."""
    client = resourcemanager_v3.ProjectsClient()
    project = client.get_project(name=f"projects/{project_id}")
    parent = project.parent
    yield project.name
    while parent and not parent.startswith("organizations/"):
        yield parent
        if parent.startswith("folders/"):
            f = resourcemanager_v3.FoldersClient().get_folder(name=parent)
            parent = f.parent
        else:
            break
    if parent:
        yield parent


def _department_folder_of(project_id: str) -> str | None:
    """Return the department folder that holds the project, or None."""
    org = f"organizations/{ORG_ID}"
    seen_org = False
    for anc in _ancestors(project_id):
        if anc in DEPARTMENT_FOLDERS:
            return anc
        if anc == org:
            seen_org = True
            break
    if not seen_org:
        log.warning(
            "walked past expected org while checking ancestry of %s", project_id
        )
    return None


def _create_lien(project_id: str) -> None:
    """Idempotent: if a lien with the same origin already exists on the
    project, skip.
    """
    client = resourcemanager_v3.LiensClient()
    parent = f"projects/{project_id}"
    for existing in client.list_liens(parent=parent):
        if existing.origin == LIEN_ORIGIN:
            log.info(
                "lien already present on %s (%s); skipping",
                project_id,
                existing.name,
            )
            return
    lien = resourcemanager_v3.Lien(
        parent=parent,
        restrictions=LIEN_RESTRICTIONS,
        origin=LIEN_ORIGIN,
        reason=LIEN_REASON,
    )
    created = client.create_lien(lien=lien)
    log.info("created lien %s on project %s", created.name, project_id)


@functions_framework.cloud_event
def handle_project_created(event: CloudEvent) -> None:
    try:
        entry = _decode_pubsub(event)
    except Exception:
        log.exception("failed to decode pubsub payload")
        return

    log.info("audit entry: %s", json.dumps(entry))

    project_id = _project_id_from_audit(entry)
    if not project_id:
        log.info(
            "audit entry has no project_id; ignoring (entry insertId=%s)",
            entry.get("insertId", "?"),
        )
        return

    log.info("CreateProject event for project_id=%s", project_id)

    try:
        department_folder = _department_folder_of(project_id)
    except Exception:
        log.exception("ancestry check failed for project %s", project_id)
        return
    if department_folder is None:
        log.info(
            "project %s is not under a department folder; skipping", project_id
        )
        return
    log.info(
        "project %s is under department folder %s",
        project_id,
        department_folder,
    )

    try:
        _create_lien(project_id)
    except Exception:
        log.exception("lien creation failed for project %s", project_id)
        raise  # let Eventarc retry per the trigger's RETRY_POLICY_RETRY
