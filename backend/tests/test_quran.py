"""Synthetic test metadata only. These fixtures are not Quran scripture."""

import asyncio
import copy
import json
import httpx
import pytest
from fastapi import HTTPException
from conftest import auth
from app import quran


@pytest.fixture
def payload():
    chapters = []
    global_number = 1
    for surah in range(1, 115):
        count = 54 if surah < 114 else 134
        ayahs = []
        for number in range(1, count + 1):
            ayahs.append(
                {
                    "number": global_number,
                    "numberInSurah": number,
                    "juz": min(30, ((global_number - 1) * 30 // 6236) + 1),
                    "text": f"TEST FIXTURE ONLY {global_number}",
                }
            )
            global_number += 1
        chapters.append(
            {
                "number": surah,
                "name": f"Test chapter {surah}",
                "englishName": f"Test chapter {surah}",
                "ayahs": ayahs,
            }
        )
    return {
        "code": 200,
        "data": {"edition": {"identifier": "quran-uthmani"}, "surahs": chapters},
    }


@pytest.fixture
def cache(monkeypatch, tmp_path):
    monkeypatch.setattr(quran, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(quran, "_lock", asyncio.Lock())
    return tmp_path


@pytest.mark.asyncio
async def test_full_text_fetch_is_deduplicated_cached_and_available_offline(
    cache, payload, monkeypatch
):
    original = httpx.AsyncClient
    calls = []

    def response(request):
        calls.append(request.url)
        assert "authorization" not in request.headers
        assert str(request.url) == "https://api.alquran.cloud/v1/quran/quran-uthmani"
        return httpx.Response(200, json=payload)

    monkeypatch.setattr(
        quran.httpx,
        "AsyncClient",
        lambda **kwargs: original(transport=httpx.MockTransport(response), **kwargs),
    )
    one, two = await asyncio.gather(quran.book(), quran.book())
    assert len(one["verses"]) == 6236 and one == two and len(calls) == 1
    assert len({v["juz"] for v in one["verses"]}) == 30
    monkeypatch.setattr(
        quran.httpx,
        "AsyncClient",
        lambda **kwargs: (_ for _ in ()).throw(
            AssertionError("Network should not be needed")
        ),
    )
    assert len((await quran.book())["verses"]) == 6236


@pytest.mark.asyncio
async def test_incomplete_book_is_never_cached_or_fabricated(
    cache, payload, monkeypatch
):
    original = httpx.AsyncClient
    payload["data"]["surahs"].pop()
    monkeypatch.setattr(
        quran.httpx,
        "AsyncClient",
        lambda **kwargs: original(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json=payload)),
            **kwargs,
        ),
    )
    with pytest.raises(HTTPException) as error:
        await quran.book()
    assert error.value.status_code == 503
    assert not list(cache.glob("*.json"))


@pytest.mark.asyncio
async def test_all_para_and_surah_routes_preserve_source_text_and_require_login(
    client, cache, payload
):
    (cache / "quran-uthmani.json").write_text(json.dumps(payload), encoding="utf-8")
    assert (await client.get("/api/quran/juz/1")).status_code == 401
    headers = await auth(client, 3)
    for number in range(1, 31):
        response = await client.get(f"/api/quran/juz/{number}", headers=headers)
        assert response.status_code == 200
        data = response.json()
        assert data["juz"] == number and data["verses"]
        assert all(
            v["juz"] == number and v["text"] == f"TEST FIXTURE ONLY {v['number']}"
            for v in data["verses"]
        )
    chapters = (await client.get("/api/quran/surahs", headers=headers)).json()
    assert len(chapters) == 114
    assert (
        len(
            (await client.get("/api/quran/surah/114", headers=headers)).json()["verses"]
        )
        == 134
    )
    assert (await client.get("/api/quran/juz/31", headers=headers)).status_code == 422
    assert (await client.get("/api/quran/surah/0", headers=headers)).status_code == 422
    assert (
        await client.get("/api/quran/juz/1?edition=untrusted-edition", headers=headers)
    ).status_code == 422


@pytest.mark.parametrize("field,value", [("number", 9), ("juz", 0), ("text", "")])
def test_corrupt_verses_rejected(payload, field, value):
    damaged = copy.deepcopy(payload)
    damaged["data"]["surahs"][0]["ayahs"][0][field] = value
    with pytest.raises(ValueError):
        quran.normalize(damaged, "quran-uthmani")
