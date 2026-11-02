from pydantic import BaseModel


class AdminSessionRequest(BaseModel):
    pin: str


class AdminSessionResponse(BaseModel):
    token: str
    expires_in: int
