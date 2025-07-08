docker run --rm -p 4318:4318 -p 8889:8889 --network 'sa-net' \
  -v "$(pwd)/otel-collector-config.yaml":/etc/otelcol/config.yaml \
  otel/opentelemetry-collector:latest
