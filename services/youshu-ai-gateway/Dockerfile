FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
ARG BUILD_VERSION=dev
ENV CGO_ENABLED=0
RUN go build -o /out/youshu-ai-gateway ./cmd/server

FROM alpine:3.20
RUN addgroup -S youshu && adduser -S youshu -G youshu
WORKDIR /app
COPY --from=build /out/youshu-ai-gateway .
USER youshu
EXPOSE 8080
CMD ["./youshu-ai-gateway"]
