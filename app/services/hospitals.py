from __future__ import annotations

import math
import time
from typing import Any

import requests


MOCK_HELP = [
    {"name": "City General Hospital", "distance": 1.2, "address": "12 Civic Ave", "lat": 31.5304, "lng": 74.3487},
    {"name": "Greenview Clinic", "distance": 2.4, "address": "45 Park Rd", "lat": 31.5404, "lng": 74.3387},
    {"name": "Northside Medical Center", "distance": 3.7, "address": "88 River St", "lat": 31.5504, "lng": 74.3287},
]

OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
HEADERS = {"User-Agent": "EmergencyAssistantApp/1.0 (hackathon-project)"}

_cache: dict[tuple, tuple[float, list[dict[str, Any]]]] = {}
CACHE_TTL = 600  # 10 minute


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _fetch_overpass(query: str) -> dict[str, Any] | None:
    for url in OVERPASS_URLS:
        try:
            r = requests.post(url, data={"data": query}, headers=HEADERS, timeout=12)
            print(f"OVERPASS {url} -> {r.status_code}")
            if r.status_code == 200:
                return r.json()
        except Exception as e:
            print(f"OVERPASS {url} error: {e!r}")
    return None


def find_nearby_hospitals(lat: float, lng: float, emergency_type: str) -> list[dict[str, Any]]:
    amenity = "police" if emergency_type == "personal_safety" else "hospital"
    key = (amenity, round(lat, 2), round(lng, 2))

    cached = _cache.get(key)
    if cached and time.time() - cached[0] < CACHE_TTL:
        return cached[1]

    query = f"""
    [out:json][timeout:10];
    (
      node["amenity"="{amenity}"](around:5000,{lat},{lng});
      way["amenity"="{amenity}"](around:5000,{lat},{lng});
      relation["amenity"="{amenity}"](around:5000,{lat},{lng});
    );
    out center;
    """

    payload = _fetch_overpass(query)
    if payload is None:
        # Sab servers fail: purana real result ho to wo, warna mock
        if cached:
            print("OVERPASS FAILED, USING STALE CACHE")
            return cached[1]
        print("OVERPASS FAILED, USING MOCK HELP")
        return MOCK_HELP[:3]

    results: list[dict[str, Any]] = []
    for element in payload.get("elements", []):
        tags = element.get("tags", {})
        if not tags.get("name"):
            continue  # unnamed items skip

        if element.get("type") == "node":
            lat_value = _to_float(element.get("lat"))
            lon_value = _to_float(element.get("lon"))
        else:
            center = element.get("center", {})
            lat_value = _to_float(center.get("lat"))
            lon_value = _to_float(center.get("lon"))

        if not lat_value or not lon_value:
            continue

        distance_km = math.sqrt((lat_value - lat) ** 2 + (lon_value - lng) ** 2) * 111.0
        if distance_km > 5.0:
            continue

        results.append({
            "name": tags["name"],
            "distance": round(distance_km, 2),
            "address": tags.get("addr:street") or tags.get("addr:full") or f"{lat_value}, {lon_value}",
            "lat": lat_value,
            "lng": lon_value,
        })

    if not results:
        print(f"REAL API RETURNED NO RESULTS ({amenity}) at {lat},{lng}, USING MOCK HELP")
        return MOCK_HELP[:3]

    results.sort(key=lambda item: item["distance"])
    results = results[:3]
    _cache[key] = (time.time(), results)
    return results