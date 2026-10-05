# Token auth dependency for the index server.
# Accepts the one-time token via the X-Auth-Token header or the auth query
# parameter (the latter for <img> tags which cannot set headers).
import secrets

from fastapi import Header, HTTPException, Query, Request


def token_verifier(token: str):
    """Build a FastAPI dependency enforcing the shared one-time token."""

    def verify(
        request: Request,
        x_auth_token: str | None = Header(default=None),
        auth: str | None = Query(default=None),
    ) -> None:
        supplied = x_auth_token or auth
        if not supplied or not secrets.compare_digest(supplied, token):
            raise HTTPException(status_code=401, detail="unauthorized")

    return verify
