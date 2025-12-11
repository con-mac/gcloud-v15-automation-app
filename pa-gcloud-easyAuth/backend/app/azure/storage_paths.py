"""
Utility helpers for mapping document names to Azure Blob Storage keys.

These helpers are used by tests to guarantee a consistent blob naming
strategy while we migrate the workload from AWS S3 to Azure Blob Storage.
"""

from __future__ import annotations

import re
from pathlib import PurePosixPath


def _normalise_service_folder(service_name: str) -> str:
    """Return a safe folder name preserving readability."""
    cleaned = re.sub(r"[^\w\s\-]", "", service_name).strip()
    # Collapse whitespace and replace with single spaces for human readability
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned.replace(" ", "_")


def build_service_blob_key(
    *,
    service_name: str,
    doc_type: str,
    gcloud_version: str,
    lot: str,
    extension: str,
    draft: bool = False,
) -> str:
    """
    Construct the canonical blob key for generated documents in Azure.

    The path mirrors the SharePoint folder taxonomy:
      GCloud {version}/PA Services/Cloud Support Services LOT {lot}/{Service}/filename
    """
    service_folder = _normalise_service_folder(service_name)
    filename = f"PA GC{gcloud_version} {doc_type} {service_name}"
    if draft:
        filename += "_draft"
    filename = f"{filename}.{extension}"

    key = PurePosixPath(
        f"GCloud {gcloud_version}",
        "PA Services",
        f"Cloud Support Services LOT {lot}",
        service_folder,
        filename,
    )
    return str(key)

