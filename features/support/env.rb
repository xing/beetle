require File.expand_path(File.dirname(__FILE__) + '/../../lib/beetle')

# Allow using Test::Unit for step assertions
# See http://wiki.github.com/aslakhellesoy/cucumber/using-testunit
require 'test/unit/assertions'
World(Test::Unit::Assertions)

After do
  redis_master_files = File.dirname(__FILE__) + "/../../tmp/redis-master-*"
  `rm -f #{redis_master_files}`
  `ruby bin/redis_configuration_client stop`
  `ruby bin/redis_configuration_server stop`
  RedisTestServer.stop_all
end
