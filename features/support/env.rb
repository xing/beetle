require File.expand_path('../../../lib/beetle', __FILE__)

# Allow using Test::Unit for step assertions
# See http://wiki.github.com/aslakhellesoy/cucumber/using-testunit
require 'test/unit/assertions'
World(Test::Unit::Assertions)

Before do
  cleanup_test_env
end

After do
  cleanup_test_env
end

def cleanup_test_env
  `ruby features/support/beetle_handler stop`
  TestDaemons::RedisConfigurationClient.stop_all
  TestDaemons::RedisConfigurationServer.stop
  TestDaemons::Redis.stop_all
  redis_master_files = tmp_path + "/redis-master-*"
  `rm -f #{redis_master_files}`
end

def redis_master_file_path(client_name)
  tmp_path + "/redis-master-#{client_name}"
end

def first_redis_configuration_client_pid
  File.read("redis_configuration_client0.pid").chomp.to_i
end

def tmp_path
  File.expand_path("../../../tmp", __FILE__)
end
