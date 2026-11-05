FROM python:3.12-slim

WORKDIR /app
RUN pip install --no-cache-dir temporalio==1.35.0
COPY workflows.py worker.py starter.py ./

# -u = unbuffered, so logs show up in `kubectl logs` immediately.
# starter.py is in the image too:  kubectl exec deploy/<name> -- python3 starter.py
CMD ["python3", "-u", "worker.py"]
