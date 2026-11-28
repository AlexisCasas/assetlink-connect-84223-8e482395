# CI-only spike: build must supply resolved immutable official Python base digest.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
WORKDIR /app
COPY --chown=0:0 probe.py /app/probe.py
USER 65532:65532
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HOME=/tmp
ENTRYPOINT ["python", "-I", "-B", "/app/probe.py"]
