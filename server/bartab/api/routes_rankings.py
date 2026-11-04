from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from bartab.api.deps import get_session, require_device
from bartab.api.schemas import ErrorResponse, RankingsResponse
from bartab.persistence.repos import drink_rankings

router = APIRouter()


@router.get(
    "/rankings",
    name="getRankings",
    response_model=RankingsResponse,
    responses={401: {"model": ErrorResponse}},
)
def get_rankings(
    _device_id: str = Depends(require_device),
    session: Session = Depends(get_session),
) -> RankingsResponse:
    rankings = drink_rankings(session)
    return RankingsResponse(overall=rankings.overall, persons=rankings.persons)
