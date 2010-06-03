require File.expand_path(File.dirname(__FILE__) + '/../../lib/beetle')

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
  redis_master_files = File.dirname(__FILE__) + "/../../tmp/redis-master-*"
  `rm -f #{redis_master_files}`

  TestDaemons::RedisConfigurationServer.stop

  TestDaemons::Redis.stop_all
end

def redis_master_file_path(client_name)
  File.expand_path(File.dirname(__FILE__) + "/../../tmp/redis-master-#{client_name}")
end

def first_redis_configuration_client_pid
  File.read("redis_configuration_client0.pid").chomp.to_i
end
