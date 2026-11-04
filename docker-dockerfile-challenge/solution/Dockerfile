# Une solution possible du challenge « Conteneuriser une application inconnue ».
# D'autres écritures sont acceptées : seule la vérification compte.
FROM python:3.13-alpine
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
RUN adduser -D app && chown app /app
USER app
ENV HOST=0.0.0.0
EXPOSE 8080
CMD ["python", "-m", "quotes"]
