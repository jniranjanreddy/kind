FROM python:3.12-slim

WORKDIR /app
RUN pip install --no-cache-dir temporalio==1.35.0
COPY workflows.py worker.py ./
