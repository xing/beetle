# frozen_string_literal: true

require "redis-client"

begin
  require "redis_client/hiredis_connection"
rescue LoadError
else
  RedisClient.register_driver(:hiredis) { RedisClient::HiredisConnection }
  RedisClient.default_driver = :hiredis
end
