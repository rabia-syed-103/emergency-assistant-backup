from __future__ import annotations
from app.services import auth_service
from collections import defaultdict
from typing import Any

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect,Depends
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from app.routers import emergency, users
from app.repository.json_store import load_json, save_json
import threading

_reload_lock = threading.Lock()


app = FastAPI(title="Emergency Backend", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(emergency.router)
app.include_router(users.router)


@app.get("/")
def root():
    return {"status": "ok", "service": "emergency-backend"}


# ---------------------------------------------------------------------------
# Realtime infra (Member 4) — location sharing + trusted contacts.
# Kept here (not a separate router) because notifications.py does a lazy
# `from app.main import trusted_contacts` import to reuse this same dict.
# These are intentionally simple dict/set structures so they can later be
# swapped for Redis without changing the API layer.
# ---------------------------------------------------------------------------

# latest_locations/subscribers are genuinely live/ephemeral (an open
# WebSocket can't survive a restart anyway), so these stay in-memory only.
latest_locations: dict[str, dict[str, Any]] = {}
subscribers: defaultdict[str, set[WebSocket]] = defaultdict(set)

# trusted_contacts and device_tokens are backed by data/contacts.json so
# they survive a server restart (previously pure in-memory dicts, wiped
# every restart — this is the fix for that).
_contacts_data = load_json(
    "contacts",
    default={
        "trusted_contacts": {"user-123": ["demo-contact-1", "demo-contact-2"]},
        "device_tokens": {},
    },
)
trusted_contacts: dict[str, list[str]] = _contacts_data.get("trusted_contacts", {})
pending_requests: dict[str, list[str]] = _contacts_data.get("pending_requests", {})

# contact_id -> real FCM device token. Populated when a person opens the
# app and it registers their device (POST /devices/register). A contact_id
# appearing in someone's trusted_contacts list does NOT mean they get
# notified — they must have ALSO registered their own device here first.
# This is the safety boundary: adding a phone number/identifier as a
# trusted contact never sends anything by itself; the person on the other
# end has to have opened the app at least once for their device to be
# reachable at all.
device_tokens: dict[str, str] = _contacts_data.get("device_tokens", {})


def _persist_contacts() -> None:
    save_json(
        "contacts",
        {
            "trusted_contacts": trusted_contacts,
            "device_tokens": device_tokens,
            "pending_requests": pending_requests,
        },
    )

def _reload_from_disk() -> None:
    with _reload_lock:
        data = load_json("contacts", default={})
        trusted_contacts.clear()
        trusted_contacts.update(data.get("trusted_contacts", {}))
        device_tokens.clear()
        device_tokens.update(data.get("device_tokens", {}))
        pending_requests.clear()
        pending_requests.update(data.get("pending_requests", {}))

        profiles = load_json("user_profiles", default={})
        auth_service._profiles.clear()
        auth_service._profiles.update(profiles)


@app.middleware("http")
async def reload_data_middleware(request, call_next):
    _reload_from_disk()
    return await call_next(request)

class ContactAddRequest(BaseModel):
    contact_id: str


class DeviceRegisterRequest(BaseModel):
    contact_id: str
    device_token: str


@app.get("/health")
async def healthcheck() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/contacts/{user_id}/add")
async def add_contact(user_id: str, payload: ContactAddRequest) -> dict[str, str]:
    cid = payload.contact_id.strip()
    if not cid:
        raise HTTPException(status_code=400, detail="contact_id is required")
    if cid == user_id:
        raise HTTPException(status_code=400, detail="You cannot add yourself")
    if cid in trusted_contacts.get(user_id, []):
        return {"user_id": user_id, "contact_id": cid, "status": "already_added"}

    pending = pending_requests.setdefault(cid, [])
    if user_id not in pending:
        pending.append(user_id)
    _persist_contacts()
    return {"user_id": user_id, "contact_id": cid, "status": "requested"}

@app.get("/contacts/{user_id}")
async def get_contacts(user_id: str) -> dict[str, Any]:
    ids = trusted_contacts.get(user_id, [])
    detailed = []
    for cid in ids:
        p = auth_service._profiles.get(cid, {})
        detailed.append({
        "uid": cid,
        "name": p.get("name") or cid,
        "email": p.get("email", ""),
        "phone_number": p.get("phone_number", ""),
    })
    return {"user_id": user_id, "contacts": ids, "contacts_detail": detailed}


@app.post("/devices/register")
async def register_device(payload: DeviceRegisterRequest) -> dict[str, str]:
    """
    Called once when the app opens (any user — whether or not they're
    anyone's trusted contact yet). Saves their real FCM device token under
    their own identifier (e.g. phone number), so that whenever someone
    else adds that identifier as a trusted contact, notify_trusted_contacts()
    can actually reach their device.
    """
    if not payload.contact_id.strip() or not payload.device_token.strip():
        raise HTTPException(status_code=400, detail="contact_id and device_token are required")

    device_tokens[payload.contact_id] = payload.device_token
    _persist_contacts()
    return {"contact_id": payload.contact_id, "status": "registered"}


@app.get("/users")
async def list_users(exclude: str | None = None) -> dict[str, Any]:
    users_list = []

    for uid, profile in auth_service._profiles.items():
        if uid == exclude:
            continue

        if uid not in device_tokens:
            continue

        users_list.append({
        "uid": uid,
        "name": profile.get("name", ""),
        "email": profile.get("email", ""),
        "phone_number": profile.get("phone_number", ""),
    })

    return {"users": users_list}


@app.get("/users/search")
async def search_users(
    q: str = "",
    exclude: str | None = None,
) -> dict[str, Any]:

    query = q.strip().lower()
    users_list = []

    for uid, profile in auth_service._profiles.items():
        if uid == exclude:
            continue

        if uid not in device_tokens:
            continue

        name = profile.get("name", "")
        email = profile.get("email", "")

        if (
            query == ""
            or query in uid.lower()
            or query in name.lower()
            or query in email.lower()
        ):
            users_list.append({
    "uid": uid,
    "name": profile.get("name", ""),
    "email": profile.get("email", ""),
    "phone_number": profile.get("phone_number", ""),
})

    return {"users": users_list}


@app.websocket("/ws/location/{user_id}")
async def location_socket(websocket: WebSocket, user_id: str) -> None:
    await websocket.accept()

    try:
        while True:
            raw_message = await websocket.receive_json()
            message_type = raw_message.get("type")
            location_fields = {"lat", "lng", "timestamp"}

            # A dashboard client can subscribe to a user's live location stream.
            if message_type == "subscribe":
                subscribers[user_id].add(websocket)
                cached = latest_locations.get(user_id)
                if cached:
                    await websocket.send_json(
                        {
                            "type": "location",
                            "user_id": user_id,
                            "location": {"lat": cached["lat"], "lng": cached["lng"]},
                            "timestamp": cached.get("timestamp"),
                        }
                    )
                continue

            # Mobile clients send periodic updates in the format {lat, lng, timestamp}.
            if set(raw_message.keys()).issuperset(location_fields):
                lat = float(raw_message["lat"])
                lng = float(raw_message["lng"])
                timestamp = str(raw_message["timestamp"])

                latest_locations[user_id] = {
                    "lat": lat,
                    "lng": lng,
                    "timestamp": timestamp,
                }

                payload = {
                    "type": "location",
                    "user_id": user_id,
                    "location": {"lat": lat, "lng": lng},
                    "timestamp": timestamp,
                }

                ack = {
                    "type": "ack",
                    "status": "received",
                    "user_id": user_id,
                    "location": {"lat": lat, "lng": lng},
                    "timestamp": timestamp,
                }
                await websocket.send_json(ack)
                await broadcast_to_subscribers(user_id, payload)
                continue

            if message_type == "location":
                nested_location = raw_message.get("location", {})
                if not isinstance(nested_location, dict):
                    await websocket.send_json({"type": "error", "error": "location payload must be an object"})
                    continue

                lat = float(nested_location.get("lat"))
                lng = float(nested_location.get("lng"))
                timestamp = str(raw_message.get("timestamp"))

                latest_locations[user_id] = {
                    "lat": lat,
                    "lng": lng,
                    "timestamp": timestamp,
                }

                payload = {
                    "type": "location",
                    "user_id": user_id,
                    "location": {"lat": lat, "lng": lng},
                    "timestamp": timestamp,
                }
                ack = {
                    "type": "ack",
                    "status": "received",
                    "user_id": user_id,
                    "location": {"lat": lat, "lng": lng},
                    "timestamp": timestamp,
                }
                await websocket.send_json(ack)
                await broadcast_to_subscribers(user_id, payload)
                continue

            await websocket.send_json({"type": "error", "error": "Unsupported message format"})

    except WebSocketDisconnect:
        subscribers[user_id].discard(websocket)
    except Exception:
        subscribers[user_id].discard(websocket)
        await websocket.close(code=1011)


async def broadcast_to_subscribers(user_id: str, payload: dict[str, Any]) -> None:
    """Send a location update to all currently connected dashboard clients for a user."""
    stale_connections: set[WebSocket] = set()

    for websocket in list(subscribers.get(user_id, set())):
        try:
            await websocket.send_json(payload)
        except RuntimeError:
            stale_connections.add(websocket)
        except WebSocketDisconnect:
            stale_connections.add(websocket)

    for stale in stale_connections:
        subscribers[user_id].discard(stale)
@app.get("/requests/incoming")
async def incoming_requests(decoded: dict = Depends(auth_service.verify_token)):
    uid = decoded["uid"]
    result = []
    for from_uid in pending_requests.get(uid, []):
        p = auth_service._profiles.get(from_uid, {})
        result.append({
            "uid": from_uid,
            "name": p.get("name") or from_uid,
            "email": p.get("email", ""),
            "phone_number": p.get("phone_number", ""),
        })
    return {"requests": result}


@app.post("/requests/{from_uid}/accept")
async def accept_request(from_uid: str, decoded: dict = Depends(auth_service.verify_token)):
    uid = decoded["uid"]
    pending = pending_requests.get(uid, [])
    if from_uid not in pending:
        raise HTTPException(status_code=404, detail="Request not found")
    pending.remove(from_uid)
    lst = trusted_contacts.setdefault(from_uid, [])
    if uid not in lst:
        lst.append(uid)
    _persist_contacts()
    return {"status": "accepted"}


@app.post("/requests/{from_uid}/decline")
async def decline_request(from_uid: str, decoded: dict = Depends(auth_service.verify_token)):
    uid = decoded["uid"]
    pending = pending_requests.get(uid, [])
    if from_uid in pending:
        pending.remove(from_uid)
        _persist_contacts()
    return {"status": "declined"}


@app.delete("/contacts/{user_id}/{contact_id}")
async def remove_contact(user_id: str, contact_id: str, decoded: dict = Depends(auth_service.verify_token)):
    if decoded["uid"] != user_id:
        raise HTTPException(status_code=403, detail="Not allowed")
    lst = trusted_contacts.get(user_id, [])
    if contact_id in lst:
        lst.remove(contact_id)
        _persist_contacts()
    return {"status": "removed"}