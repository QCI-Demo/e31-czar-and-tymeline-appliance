# E31 Retrieval Service — Jetson AGX Thor (NVIDIA runtime)
# Includes Qdrant client libraries and vector store path for local retrieval.
FROM nvcr.io/nvidia/l4t-base:r35.2.1

WORKDIR /app

# Install Python 3.12 (L4T r35.2.1 / Ubuntu 20.04 has no python3.12 in apt for arm64)
# qdrant-client is installed via pip (PyPI); story lists it alongside apt packages.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates xz-utils \
    && curl -fsSL -o /tmp/cpython.tgz \
        "https://github.com/astral-sh/python-build-standalone/releases/download/20260623/cpython-3.12.13%2B20260623-aarch64-unknown-linux-gnu-install_only.tar.gz" \
    && mkdir -p /opt \
    && tar -xzf /tmp/cpython.tgz -C /opt \
    && rm /tmp/cpython.tgz \
    && /opt/python/bin/python3.12 -m ensurepip --upgrade \
    && /opt/python/bin/python3.12 -m pip install --no-cache-dir --upgrade pip \
    && ln -sf /opt/python/bin/python3.12 /usr/local/bin/python3 \
    && ln -sf /opt/python/bin/python3.12 /usr/local/bin/python3.12 \
    && ln -sf /opt/python/bin/pip3 /usr/local/bin/pip3 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/python/bin:${PATH}"

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY src/ ./

ENV NVIDIA_VISIBLE_DEVICES=all
ENV VECTOR_STORE_PATH=/data/vectors

EXPOSE 8081

ENTRYPOINT ["python3", "-m", "retrieval.main"]
