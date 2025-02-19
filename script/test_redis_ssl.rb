require 'redis'
require 'openssl'

redis = Redis.new(
  host: 'localhost', # Or your Redis server hostname
  port: 6379,
  ssl: true,
  ssl_params: {
    verify_mode: OpenSSL::SSL::VERIFY_NONE # Disable verification
  }
)

puts redis.ping
