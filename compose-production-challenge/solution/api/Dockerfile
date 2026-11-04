FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
RUN adduser -D -u 10001 appuser
USER appuser
CMD ["python", "-u", "app.py"]
