require File.expand_path(File.dirname(__FILE__) + '/../../lib/beetle')

# Allow using Test::Unit for step assertions
# See http://wiki.github.com/aslakhellesoy/cucumber/using-testunit
require 'test/unit/assertions'
World(Test::Unit::Assertions)

Before do
  $PIDS_TO_KILL = []
end

After do
  RedisTestServer.stop_all
  $PIDS_TO_KILL.each{ |pid| `kill #{pid}` }
end
