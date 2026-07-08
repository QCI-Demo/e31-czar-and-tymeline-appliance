FROM nvcr.io/nvidia/l4t-base:r35.2.1

WORKDIR /app

RUN apt-get update && apt-get install -y python3.12 python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY src/ ./

ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8084

ENTRYPOINT ["python3", "-m", "eval.main"]
