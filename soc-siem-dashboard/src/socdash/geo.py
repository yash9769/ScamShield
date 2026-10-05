"""Great-circle distance, shared by the synthetic impossible-travel scenario
and the impossible-travel detection rule so both agree on what "far apart"
means."""

from __future__ import annotations

from math import asin, cos, radians, sin, sqrt

EARTH_RADIUS_KM = 6371.0

# Approximate country centroids. Shared by the synthetic impossible-travel
# scenario (generator/entities.py) and the impossible-travel detection rule
# so both agree on what "far apart" means.
COUNTRY_GEO: dict[str, tuple[float, float]] = {
    "India": (20.5937, 78.9629),
    "United States": (37.0902, -95.7129),
    "Russia": (61.5240, 105.3188),
    "China": (35.8617, 104.1954),
    "Germany": (51.1657, 10.4515),
    "Brazil": (-14.2350, -51.9253),
    "Nigeria": (9.0820, 8.6753),
    "Netherlands": (52.1326, 5.2913),
    "Singapore": (1.3521, 103.8198),
    "United Kingdom": (55.3781, -3.4360),
    "Vietnam": (14.0583, 108.2772),
    "Ukraine": (48.3794, 31.1656),
    "South Africa": (-30.5595, 22.9375),
    "Japan": (36.2048, 138.2529),
    "Canada": (56.1304, -106.3468),
}


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1, lon1, lat2, lon2 = map(radians, (lat1, lon1, lat2, lon2))
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_KM * asin(sqrt(a))


def implied_speed_kmh(lat1: float, lon1: float, lat2: float, lon2: float, hours: float) -> float:
    if hours <= 0:
        hours = 1 / 3600  # clamp to 1 second so same-timestamp events don't divide by zero
    return haversine_km(lat1, lon1, lat2, lon2) / hours
