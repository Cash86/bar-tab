from fastapi import APIRouter

router = APIRouter()


@router.get("/health", name="getHealth")
def health() -> dict[str, str]:
    return {"status": "ok"}
