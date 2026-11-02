import hashlib
import json
from dataclasses import asdict

from fastapi import APIRouter, Depends, Header, Response
from sqlalchemy.orm import Session

from bartab.api.deps import get_session, require_device
from bartab.api.schemas import CatalogResponse, ErrorResponse
from bartab.persistence.repos import get_catalog

router = APIRouter()


def _etag(body: dict) -> str:
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _matches(if_none_match: str | None, etag: str) -> bool:
    if not if_none_match:
        return False
    candidates = [c.strip() for c in if_none_match.split(",")]
    return any(c in ("*", etag, f'"{etag}"') for c in candidates)


@router.get(
    "/catalog",
    name="getCatalog",
    response_model=CatalogResponse,
    responses={
        304: {
            "description": "Not modified",
            "headers": {"ETag": {"description": "Catalog version", "schema": {"type": "string"}}},
        },
        401: {"model": ErrorResponse},
    },
)
def read_catalog(
    response: Response,
    _device_id: str = Depends(require_device),
    session: Session = Depends(get_session),
    if_none_match: str | None = Header(default=None),
) -> CatalogResponse | Response:
    body = asdict(get_catalog(session))
    etag = _etag(body)
    headers = {"ETag": f'"{etag}"'}
    if _matches(if_none_match, etag):
        return Response(status_code=304, headers=headers)
    response.headers.update(headers)
    return CatalogResponse(**body, etag=etag)
