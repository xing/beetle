require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class ConfiguratorTest < Test::Unit::TestCase

    def setup
      Configurator.active_master = nil
      configurator = Configurator.new
      configurator.client.deduplication_store.redis_instances = []
    end

    test "process should forward to class methods" do
      message = mock('message', :data => '{"op":"give_master", "somevariable": "somevalue"}')
      Configurator.any_instance.stubs(:message).returns(message)
      Configurator.expects(:give_master).with({"somevariable" => "somevalue"})
      Configurator.new.process()
    end

    test "find_active_master should return the first working redis" do
      non_working_redis  = mock('redis')
      working_redis      = mock('redis', :info => 'ok')
      non_working_redis.expects(:info).raises(Timeout::Error)
      configurator = Configurator.new
      configurator.client.deduplication_store.redis_instances = [non_working_redis, working_redis]
      Configurator.find_active_master
      assert_equal working_redis, Configurator.active_master
    end

    test "find_active_master should return if the current active_master if it is still active set" do
      first_working_redis      = mock('redis1')
      first_working_redis.expects(:info).never
      second_working_redis     = mock('redis2', :info => 'ok')

      configurator = Configurator.new
      configurator.client.deduplication_store.redis_instances = [first_working_redis, second_working_redis]
      Configurator.active_master = second_working_redis
      Configurator.find_active_master
      assert_equal second_working_redis, Configurator.active_master
    end

    test "find_active_master should retry to reach the current master if it doesn't respond" do
    end

    test "find_active_master should finally give up to reach the current master after xxx seconds" do
    end

    test "after giving up the current master, find_active_master should try to reach every known redis server until it finds a working one" do
    end

    test "find_active_master should not change the current master until it starts to propose a new master" do
    end

    test "give master should return the current master" do
    end

    test "proposing a new master should set the current master to nil" do
    end
  end
end