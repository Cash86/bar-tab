from pathlib import Path
from typing import Any

from pydantic import Field, field_validator
from pydantic.fields import FieldInfo
from pydantic_settings import (
    BaseSettings,
    DotEnvSettingsSource,
    EnvSettingsSource,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)

MIN_KEY_LENGTH = 32


class _CommaListMixin:
    """Reads device_keys from comma-separated values instead of JSON."""

    def prepare_field_value(
        self, field_name: str, field: FieldInfo, value: Any, value_is_complex: bool
    ) -> Any:
        if field_name == "device_keys" and isinstance(value, str):
            return [part.strip() for part in value.split(",") if part.strip()]
        return super().prepare_field_value(field_name, field, value, value_is_complex)  # type: ignore[misc]


class _CommaListEnvSource(_CommaListMixin, EnvSettingsSource):
    pass


class _CommaListDotEnvSource(_CommaListMixin, DotEnvSettingsSource):
    pass


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="BARTAB_", env_file=".env", extra="ignore")

    public_url: str
    db_path: Path
    data_dir: Path
    device_keys: list[str] = Field(min_length=1)
    initial_admin_pin: str | None = Field(default=None, pattern=r"^\d{4,8}$")
    tz: str = "Europe/Berlin"
    smtp_host: str | None = None
    smtp_port: int | None = None
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_from: str | None = None
    monthly_report_day: int = Field(default=1, ge=1, le=28)
    monthly_report_time: str = Field(default="08:00", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")

    @field_validator("device_keys")
    @classmethod
    def _keys_long_enough(cls, keys: list[str]) -> list[str]:
        if any(len(key) < MIN_KEY_LENGTH for key in keys):
            raise ValueError(f"each device key must be at least {MIN_KEY_LENGTH} characters")
        return keys

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        return (
            init_settings,
            _CommaListEnvSource(settings_cls),
            _CommaListDotEnvSource(
                settings_cls,
                env_file=dotenv_settings.env_file,  # type: ignore[attr-defined]
                env_file_encoding=dotenv_settings.env_file_encoding,  # type: ignore[attr-defined]
            ),
            file_secret_settings,
        )
