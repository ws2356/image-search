docker run --rm -p 9090:9090 --network 'sa-net' \
  -v "$(pwd)/prometheus.yml":/etc/prometheus/prometheus.yml \
  prom/prometheus
