FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PORT=8080
WORKDIR /srv

RUN useradd --system --uid 10001 --no-create-home appuser
COPY app/server.py /srv/server.py
USER 10001

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status==200 else 1)"

CMD ["python", "/srv/server.py"]
