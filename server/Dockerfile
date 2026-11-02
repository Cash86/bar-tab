FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    BARTAB_DB_PATH=/data/bartab.db BARTAB_DATA_DIR=/data
WORKDIR /app
COPY pyproject.toml alembic.ini ./
COPY bartab ./bartab
COPY alembic ./alembic
# Starts as root only to chown /data; the entrypoint then drops to the unprivileged user.
RUN pip install . \
    && useradd --system --uid 10001 --no-create-home bartab \
    && mkdir /data && chown bartab /data
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
VOLUME /data
EXPOSE 8000
ENTRYPOINT ["docker-entrypoint.sh"]
