# Une solution possible du challenge « Réduire et accélérer une image existante ».
# D'autres écritures sont acceptées, par exemple une image finale alpine:3.22.
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /slow .

FROM scratch
COPY --from=build /slow /slow
EXPOSE 8080
CMD ["/slow"]
