from __future__ import annotations

import json
import os
from typing import Any

import firebase_admin
from firebase_admin import messaging

from app import firebase_init  # noqa: F401 -- import triggers Firebase Admin init


def _location_link(location: dict[str, Any]) -> str:
    """Turns {lat, lng} into a tappable Google Maps link instead of raw
    coordinates, so the person receiving the alert can open it directly."""
    lat = location.get("lat")
    lng = location.get("lng")
    if lat is None or lng is None:
        return "Location unavailable"
    return f"https://maps.google.com/?q={lat},{lng}"


def notify_trusted_contacts(user_id: str, severity: int, emergency_type: str, location: dict[str, Any]) -> list[str]:
    """Send real push notifications to each trusted contact for a user via Firebase.

    Only contacts the user has explicitly added (trusted_contacts[user_id]) are
    ever considered, AND only those who have separately registered a real
    device token via POST /devices/register (done once when they open the
    app themselves) actually receive anything. Being added to someone's
    trusted contacts list never triggers a notification by itself — the
    contact has to have opened the app at least once first. Anyone not yet
    registered is safely skipped, never silently messaged some other way.
    """
    from app.main import device_tokens, trusted_contacts, _persist_contacts
    from app.services import auth_service

    contacts = trusted_contacts.get(user_id, [])
    notified: list[str] = []

    sender = auth_service._profiles.get(user_id, {})
    sender_name = sender.get("name") or user_id

    for contact_id in contacts:
        device_token = device_tokens.get(contact_id)
        if not device_token:
            print(f"No registered device token for {contact_id}, skipping.")
            continue

        title = f"EMERGENCY ALERT - {sender_name}"
        body = (
            f"Type: {emergency_type}. Severity: {severity}. "
            f"Location: {_location_link(location)}"
        )

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={
                "type": "emergency_alert",
                "user_id": user_id,
                "user_name": sender_name,
                "phone_number": sender.get("phone_number", ""),
                "blood_group": sender.get("blood_group", ""),
                "severity": str(severity),
                "emergency_type": str(emergency_type),
                "lat": str(location.get("lat", "")),
                "lng": str(location.get("lng", "")),
            },
            android=messaging.AndroidConfig(priority="high"),
            token=device_token,
        )

        try:
            response = messaging.send(message)
            print(f"Successfully sent notification to {contact_id}: {response}")
            notified.append(contact_id)
        except messaging.UnregisteredError:
            print(f"Stale token for {contact_id}, removing.")
            device_tokens.pop(contact_id, None)
            _persist_contacts()
        except Exception as e:
            print(f"Failed to notify {contact_id}: {e}")

    return notified