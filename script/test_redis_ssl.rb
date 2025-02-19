require 'beetle'

# make sure to run the server with docker compose -f docker-compose-redis-ssl.yml up

config = Beetle::Configuration.new
config.redis_tls = true
config.redis_tls_ca_file = File.expand_path('docker/tls/test_ca.crt', __dir__)
config.redis_tls_ca_path = File.expand_path('docker/tls', __dir__)
config.redis_server = "localhost:6379"
dedup_store = Beetle::DeduplicationStore.new(config)
puts dedup_store.ping
