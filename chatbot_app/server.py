"""Authenticated programmatic Hayhooks application."""

from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse
from hayhooks import (
    create_app,
    run_app,
)
from hayhooks.settings import settings

from chatbot_app.auth import (
    get_auth_registry,
    identity_scope,
)


_PUBLIC_PATHS = {
    "/status",
    "/healthcheck/run",
}

_BLOCKED_EXACT_PATHS = {
    "/deploy-yaml",
    "/deploy_files",
}


def _normalize(
    path: str,
) -> str:
    path = (
        f"/{path.lstrip('/')}"
        if path
        else "/"
    )

    return (
        path.rstrip("/")
        or "/"
    )


def _relative_path(
    path: str,
    root_path: str,
) -> str:
    candidate = _normalize(
        path
    )

    root = _normalize(
        root_path
    )

    if root != "/":
        if candidate == root:
            return "/"

        if candidate.startswith(
            f"{root}/"
        ):
            candidate = candidate[
                len(root):
            ]

    return _normalize(
        candidate
    )


def _blocked_management_path(
    path: str,
) -> bool:
    return (
        path in _BLOCKED_EXACT_PATHS
        or path.startswith(
            "/undeploy/"
        )
    )


def _unauthorized() -> JSONResponse:
    return JSONResponse(
        status_code=401,
        content={
            "detail": "Unauthorized",
        },
        headers={
            "WWW-Authenticate": "Bearer",
        },
    )


def create_authenticated_app():
    registry = get_auth_registry()
    app = create_app()

    @app.middleware("http")
    async def authentication_middleware(
        request: Request,
        call_next,
    ):
        path = _relative_path(
            request.url.path,
            settings.root_path,
        )

        # Browser CORS preflight must reach CORSMiddleware.
        if request.method == "OPTIONS":
            return await call_next(
                request
            )

        if path in _PUBLIC_PATHS:
            return await call_next(
                request
            )

        # Production pipelines are deployed only at startup.
        # Runtime mutation routes are intentionally unavailable.
        if _blocked_management_path(
            path
        ):
            return JSONResponse(
                status_code=404,
                content={
                    "detail": "Not Found",
                },
            )

        authorization = request.headers.get(
            "Authorization",
            "",
        )

        parts = authorization.split()

        if (
            len(parts) != 2
            or parts[0].lower()
            != "bearer"
        ):
            return _unauthorized()

        identity = registry.authenticate(
            parts[1]
        )

        if identity is None:
            return _unauthorized()

        with identity_scope(
            identity
        ):
            return await call_next(
                request
            )

    return app


hayhooks = create_authenticated_app()


if __name__ == "__main__":
    run_app(
        hayhooks
    )
