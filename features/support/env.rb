require File.expand_path(File.dirname(__FILE__) + '/../../lib/beetle')

# Allow using Test::Unit for step assertions
# See http://wiki.github.com/aslakhellesoy/cucumber/using-testunit
require 'test/unit/assertions'
World(Test::Unit::Assertions)

After do
  `ruby bin/redis_configuration_client stop`
  `ruby bin/redis_configuration_server stop`
  RedisTestServer.stop_all
end
