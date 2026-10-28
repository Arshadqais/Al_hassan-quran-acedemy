"""Unmodified Uthmani text from AlQuran Cloud, cached on the academy machine."""

import asyncio
import json
import os
from pathlib import Path
import tempfile
from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from app.security import current_user

PROVIDER = "https://api.alquran.cloud"
EDITIONS = {
    "quran-uthmani": "Arabic · Uthmani",
    "en.sahih": "English · Sahih International",
    "ur.jalandhry": "Urdu · Jalandhry",
}
CACHE_DIR = Path(os.environ.get("ACADEMY_DATA_DIR", Path(__file__).resolve().parents[1] / ".local")) / "quran"
_lock = asyncio.Lock()
router = APIRouter(prefix="/api/quran", tags=["Quran"])


def normalize(payload, edition):
    """Reject incomplete/mislabelled books; never synthesize missing Quran text."""
    data = payload["data"]
    if payload.get("code") != 200 or data["edition"]["identifier"] != edition:
        raise ValueError("Unexpected edition")
    chapters = data["surahs"]
    if len(chapters) != 114 or [s["number"] for s in chapters] != list(range(1, 115)):
        raise ValueError("Incomplete Surahs")
    verses = []
    for surah in chapters:
        if not surah["ayahs"] or [a["numberInSurah"] for a in surah["ayahs"]] != list(
            range(1, len(surah["ayahs"]) + 1)
        ):
            raise ValueError("Incomplete Surah verses")
        for ayah in surah["ayahs"]:
            if not isinstance(ayah["text"], str) or not ayah["text"].strip():
                raise ValueError("Missing verse")
            if not 1 <= ayah["juz"] <= 30:
                raise ValueError("Invalid Juz")
            verses.append(
                {
                    "number": ayah["number"],
                    "text": ayah["text"],
                    "ayah": ayah["numberInSurah"],
                    "juz": ayah["juz"],
                    "surah": surah["number"],
                    "surah_name": surah["name"],
                    "surah_english": surah["englishName"],
                }
            )
    if [v["number"] for v in verses] != list(range(1, 6237)) or {
        v["juz"] for v in verses
    } != set(range(1, 31)):
        raise ValueError("Incomplete Quran")
    return {
        "edition": edition,
        "source": "AlQuran Cloud / Tanzil",
        "source_url": "https://alquran.cloud",
        "verses": verses,
    }


async def book(edition="quran-uthmani"):
    if edition not in EDITIONS:
        raise HTTPException(422, "Unsupported Quran edition")
    async with _lock:
        path = CACHE_DIR / f"{edition}.json"
        if path.exists():
            try:
                payload = json.loads(
                    await asyncio.to_thread(path.read_text, encoding="utf-8")
                )
                return normalize(payload, edition)
            except (ValueError, KeyError, TypeError, OSError):
                # A damaged cache is never served as Quran text.
                pass
        try:
            async with httpx.AsyncClient(timeout=45, follow_redirects=False) as client:
                response = await client.get(f"{PROVIDER}/v1/quran/{edition}")
                response.raise_for_status()
                if len(response.content) > 15_000_000:
                    raise ValueError("Oversized response")
                payload = response.json()
            result = normalize(payload, edition)
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            raise HTTPException(
                503,
                "The Quran provider is unavailable and no valid local copy is cached. Connect to the internet and try again.",
            ) from None
        CACHE_DIR.mkdir(parents=True, exist_ok=True)

        # Atomic replace keeps interrupted downloads from corrupting a good cache.
        def store():
            with tempfile.NamedTemporaryFile(
                "w", dir=CACHE_DIR, delete=False, encoding="utf-8"
            ) as handle:
                temporary = Path(handle.name)
                json.dump(payload, handle, ensure_ascii=False)
            try:
                os.replace(temporary, path)
            finally:
                temporary.unlink(missing_ok=True)

        try:
            await asyncio.to_thread(store)
        except OSError:
            raise HTTPException(
                503,
                "Quran was downloaded, but the local cache directory is not writable.",
            ) from None
        return result


@router.get("/catalog")
async def catalog(user=Depends(current_user)):
    return {
        "paras": list(range(1, 31)),
        "editions": EDITIONS,
        "source": "AlQuran Cloud / Tanzil",
        "cached": {e: (CACHE_DIR / f"{e}.json").exists() for e in EDITIONS},
    }


@router.get("/juz/{number}")
async def juz(
    number: int,
    edition: Annotated[str, Query()] = "quran-uthmani",
    user=Depends(current_user),
):
    if not 1 <= number <= 30:
        raise HTTPException(422, "Choose a para from 1 to 30")
    result = await book(edition)
    return {
        **{k: v for k, v in result.items() if k != "verses"},
        "juz": number,
        "verses": [v for v in result["verses"] if v["juz"] == number],
    }


@router.get("/surahs")
async def surahs(user=Depends(current_user)):
    result = await book()
    chapters = {}
    for verse in result["verses"]:
        row = chapters.setdefault(
            verse["surah"],
            {
                "number": verse["surah"],
                "name": verse["surah_name"],
                "english_name": verse["surah_english"],
                "ayahs": 0,
            },
        )
        row["ayahs"] += 1
    return list(chapters.values())


@router.get("/surah/{number}")
async def surah(
    number: int,
    edition: Annotated[str, Query()] = "quran-uthmani",
    user=Depends(current_user),
):
    if not 1 <= number <= 114:
        raise HTTPException(422, "Choose a Surah from 1 to 114")
    result = await book(edition)
    return {
        **{k: v for k, v in result.items() if k != "verses"},
        "surah": number,
        "verses": [v for v in result["verses"] if v["surah"] == number],
    }
