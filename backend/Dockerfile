FROM rust:1.95-slim AS builder

RUN apt-get update && apt-get install -y pkg-config libssl-dev curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src benches && echo "fn main() {}" > src/main.rs && echo "fn main() {}" > benches/chunking_bench.rs
RUN cargo build --release && rm -rf src benches target/release/deps/trustrag*

COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/trustrag-backend /usr/local/bin/trustrag-backend
COPY --from=builder /app/migrations /app/migrations

WORKDIR /app
ENV RUST_LOG=trustrag_backend=info,tower_http=info

EXPOSE 8080
CMD ["trustrag-backend"]
