# syntax=docker/dockerfile:1
#
# TaskApp Backend (Flask + Gunicorn) — multi-stage image
# Lesson references: slides 18-20 (Containerizing Applications, Multi-Stage Builds)
#
# Stage 1 builds the Python dependencies into an isolated virtualenv.
# Stage 2 is a slim runtime that copies ONLY the venv + app code — no build
# toolchain, no pip cache, no tests. Smaller image = faster pulls, smaller
# attack surface.

############################
# Stage 1 — builder
############################
FROM python:3.11-slim AS builder

# PYTHONDONTWRITEBYTECODE: don't litter .pyc files.  PYTHONUNBUFFERED: stream
# logs straight to stdout so `docker logs` shows them in real time.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Build deps into a self-contained venv we can lift into the runtime stage.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy requirements FIRST (changes rarely) so this layer is cached across code
# edits — order layers by change frequency (lesson 02-dockerfile).
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

############################
# Stage 2 — runtime
############################
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Never run as root in a container. Create an unprivileged user (slide 19).
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

# Bring in the pre-built virtualenv from the builder stage.
COPY --from=builder /opt/venv /opt/venv

# Copy only what the app needs at runtime.
COPY app/ ./app/
COPY migrations/ ./migrations/
COPY alembic.ini run.py ./
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chown -R appuser:appuser /app

USER appuser

# Document the port the app listens on (slide 19). Publishing is done at run time.
EXPOSE 5000

# Container health uses the app's own DB-aware endpoint (app/routes.py:/health,
# served under the /api prefix). Compose/Portainer key "service_healthy" off this.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; \
import urllib.error; \
sys.exit(0) if urllib.request.urlopen('http://localhost:5000/api/health', timeout=4).status == 200 else sys.exit(1)" \
  || exit 1

# The entrypoint runs DB migrations, then execs the CMD (gunicorn).
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "--workers", "3", "--bind", "0.0.0.0:5000", "--access-logfile", "-", "run:app"]
