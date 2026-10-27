import pytest
from dotenv import dotenv_values
from app import integrations


def test_video_configuration_is_private_and_preserves_database_settings(
    tmp_path, monkeypatch
):
    path = tmp_path / ".env"
    path.write_text("DATABASE_PASSWORD=existing-test-password\n")
    monkeypatch.setattr(integrations, "ENV_PATH", path)
    integrations.save_video(
        "wss://test-provider.example", "fake-api-key", "fake-test-secret"
    )
    result = dotenv_values(path)
    assert result["DATABASE_PASSWORD"] == "existing-test-password"
    assert result["LIVEKIT_URL"] == "wss://test-provider.example"
    assert result["LIVEKIT_API_SECRET"] == "fake-test-secret"
    assert path.stat().st_mode & 0o777 == 0o600
    with pytest.raises(ValueError):
        integrations.save_video(
            "wss://provider.example", "key\nDATABASE_PASSWORD=changed", "secret"
        )
    assert dotenv_values(path)["DATABASE_PASSWORD"] == "existing-test-password"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "url",
    [
        "ws://localhost:7880",
        "https://provider.example",
        "wss://user@provider.example",
        "wss://:secret@provider.example",
    ],
)
async def test_video_requires_public_tls_endpoint_without_credentials_in_url(url):
    with pytest.raises(ValueError):
        await integrations.verify_video(url, "test-key", "test-secret")
