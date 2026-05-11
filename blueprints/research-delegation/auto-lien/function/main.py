"""Auto-lien Cloud Function.

Triggered on every CreateProject audit log event published to the Pub/Sub
topic by the org-level aggregated log sink. For each new project that lives
under the configured Teams folder subtree, attaches a deletion lien.

The lien blocks resourcemanager.projects.delete until removed by an identity
holding roles/resourcemanager.lienModifier on the project (or this function's
SA, since it has lienModifier on the Teams folder ancestor).

Environment variables (set by Terraform):
    TEAMS_FOLDER_ID  Folder ID under which projects qualify for auto-lien.
    LIEN_REASON      Reason text stored on the lien.
    ORG_ID           Org ID — used as a sanity-check upper bound when walking
                     a project's ancestry.
"""

from __future__ import annotations

import base64
import json
import logging
import os
from typing import Iterable

import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import resourcemanager_v3

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

TEAMS_FOLDER_ID = os.environ["TEAMS_FOLDER_ID"]
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
    project_id = (
        payload.get("request", {}).get("project", {}).get("projectId")
        or payload.get("response", {}).get("projectId")
    )
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


def _is_under_teams_folder(project_id: str) -> bool:
    target = f"folders/{TEAMS_FOLDER_ID}"
    org = f"organizations/{ORG_ID}"
    seen_org = False
    for anc in _ancestors(project_id):
        if anc == target:
            return True
        if anc == org:
            seen_org = True
            break
    if not seen_org:
        log.warning("walked past expected org while checking ancestry of %s", project_id)
    return False


def _create_lien(project_id: str) -> None:
    """Idempotent: if a lien with the same origin already exists on the project, skip."""
    client = resourcemanager_v3.LiensClient()
    parent = f"projects/{project_id}"
    for existing in client.list_liens(parent=parent):
        if existing.origin == LIEN_ORIGIN:
            log.info("lien already present on %s (%s); skipping", project_id, existing.name)
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

    project_id = _project_id_from_audit(entry)
    if not project_id:
        log.info("audit entry has no project_id; ignoring (entry insertId=%s)",
                 entry.get("insertId", "?"))
        return

    log.info("CreateProject event for project_id=%s", project_id)

    try:
        if not _is_under_teams_folder(project_id):
            log.info("project %s is not under teams folder %s; skipping",
                     project_id, TEAMS_FOLDER_ID)
            return
    except Exception:
        log.exception("ancestry check failed for project %s", project_id)
        return

    try:
        _create_lien(project_id)
    except Exception:
        log.exception("lien creation failed for project %s", project_id)
        raise  # let Eventarc retry per the trigger's RETRY_POLICY_RETRY
