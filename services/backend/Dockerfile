# KIITPulse backend
#
# Two-stage build so the runtime image carries the binary and nothing else.
# A campus service handles signed-out students' traffic; a small image means a
# fast cold start when a hostel wifi outage ends and everyone reconnects at once.

FROM golang:1.27-alpine AS build
WORKDIR /src

# Dependencies first: this layer is cached until go.mod changes, so editing a
# handler does not re-download the module graph.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO off so the binary is static and runs on a scratch-like base.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server .

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server

# nonroot:65532 is baked into the distroless image; running as root in a
# container that holds a JWT secret is not worth the convenience.
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app/server"]
