"""
auth_service.py

Firebase Authentication token verification + local profile storage.

Sign-up, login, and password hashing are all handled by Firebase Auth
itself, on the frontend, via the Firebase Auth SDK (e.g.
createUserWithEmailAndPassword / signInWithEmailAndPassword). This
backend never sees a raw or hashed password — Firebase's own servers
handle that, which is far safer than hand-rolling password hashing.

This backend's job is only:
1. Verify the Firebase ID token the frontend sends with each request
   (proves the request really is from that signed-in user) via
   verify_token(), a FastAPI dependency.
2. Store/retrieve the extra profile fields Firebase Auth doesn't hold
   (name, phone_number, blood_group, dob), keyed by the verified uid.
"""

from __future__ import annotations

from typing import Any, Optional

from fastapi import Header, HTTPException
from firebase_admin import auth as firebase_auth

from app import firebase_init  # noqa: F401 -- import triggers Firebase Admin init
from app.repository.json_store import load_json, save_json

_profiles: dict[str, dict[str, Any]] = load_json("user_profiles", default={})


def _persist() -> None:
    save_json("user_profiles", _profiles)


def verify_token(authorization: Optional[str] = Header(None)) -> dict[str, Any]:
    """
    FastAPI dependency. Reads the `Authorization: Bearer <firebase_id_token>`
    header, verifies it against Firebase, and returns the decoded token
    (contains at least "uid" and, for email/password sign-in, "email").
    Raises 401 if the header is missing or the token is invalid/expired.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or malformed Authorization header")

    id_token = authorization.removeprefix("Bearer ").strip()
    try:
         decoded = firebase_auth.verify_id_token(id_token, clock_skew_seconds=60)
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"Invalid or expired token: {exc}")

    return decoded


def save_profile(
    uid: str, name: str, email: str, phone_number: str, blood_group: str, dob: str
) -> dict[str, Any]:
    profile = {
        "uid": uid,
        "name": name,
        "email": email,
        "phone_number": phone_number,
        "blood_group": blood_group,
        "dob": dob,
    }
    _profiles[uid] = profile
    _persist()
    return profile


def get_profile(uid: str) -> Optional[dict[str, Any]]:
    return _profiles.get(uid)
