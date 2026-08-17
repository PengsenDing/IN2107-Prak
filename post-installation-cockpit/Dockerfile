# Container image for the SSH-based features of the dashboard.
# The SAP GUI launcher needs a native Windows SAP GUI installation and does
# not work inside a container; run the app natively for that (see README).
FROM python:3.12-slim

# ssh/scp are invoked as subprocesses by the app.
RUN apt-get update \
    && apt-get install --no-install-recommends -y openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user; ~/.ssh is expected to be mounted read-only.
RUN useradd --create-home app
USER app
WORKDIR /app

COPY --chown=app requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt
ENV PATH="/home/app/.local/bin:${PATH}"

COPY --chown=app . .

EXPOSE 8501
HEALTHCHECK CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8501/_stcore/health')"]
CMD ["streamlit", "run", "app.py", "--server.headless", "true", "--server.address", "0.0.0.0"]
