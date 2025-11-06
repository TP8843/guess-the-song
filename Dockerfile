FROM golang:1.25-bookworm AS builder

COPY . /app

WORKDIR /app

RUN apt-get update
RUN apt-get install libopus-dev -y

RUN go mod download

RUN CGO_ENABLED=1 GOOS=linux go build -o /server

FROM debian:bookworm

WORKDIR /

RUN apt-get update
RUN apt-get install ffmpeg -y

COPY --from=builder /server /server

CMD ["/server"]