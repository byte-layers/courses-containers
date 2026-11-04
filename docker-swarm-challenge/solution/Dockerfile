# L'image des tâches 2 et 3. Construire avec :
#   docker build -t layers-l9-svc:1 --build-arg VERSION=1 .
#   docker build -t layers-l9-svc:2 --build-arg VERSION=2 .
FROM busybox:1.37
ARG VERSION=1
ENV VERSION=$VERSION
CMD ["sh", "-c", "mkdir -p /www; echo \"VERSION-$VERSION\" > /www/index.html; exec httpd -f -p 8000 -h /www"]
