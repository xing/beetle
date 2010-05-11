require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationServerProcessMethodTest < Test::Unit::TestCase
    test "should forward incoming messages to class methods" do
      message = mock('message', :data => '{"op":"give_master", "somevariable": "somevalue"}')
      server = RedisConfigurationServer.new
      server.stubs(:message).returns(message)
      RedisConfigurationServer.expects(:give_master).with({"somevariable" => "somevalue"})
      server.process()
    end
  end

  class RedisConfigurationServerActiveMasterReachableMethodTest < Test::Unit::TestCase

    def setup
      stub_redis_configuration_server_class
      EM.stubs(:add_timer)
    end

    def teardown
      RedisConfigurationServer.alive_servers = {}
    end

    test "should return false if no current active_master set" do
      assert !RedisConfigurationServer.active_master_reachable?
    end

    test "should return false if active_master not reachable" do
      non_reachable_redis = redis_stub('non_reachable_redis')
      non_reachable_redis.stubs(:info).returns(false)
      RedisConfigurationServer.active_master = non_reachable_redis
      RedisConfigurationServer.client.config.redis_configuration_master_retries = 1
      RedisConfigurationServer.client.config.redis_configuration_master_retry_timeout = 1
      
      assert !RedisConfigurationServer.active_master_reachable?
    end

    test "should return true if the current active_master is reachable" do
      first_working_redis      = redis_stub('redis1')
      first_working_redis.expects(:info).never
      second_working_redis     = redis_stub('redis2', :info => 'ok') # enough to make reachable? happy

      RedisConfigurationServer.client.deduplication_store.redis_instances = [first_working_redis, second_working_redis]
      RedisConfigurationServer.active_master = second_working_redis
      assert RedisConfigurationServer.active_master_reachable?
    end
  end

  class RedisConfigurationServerFindActiveMasterTest < Test::Unit::TestCase

    def setup
      stub_redis_configuration_server_class
      EM.stubs(:add_timer)
    end

    def teardown
      RedisConfigurationServer.alive_servers = {}
    end

    test "find_active_master should retry to reach the current master if it doesn't respond" do
      redis = redis_stub('redis')
      redis.expects(:info).times(2).raises(Timeout::Error).then.returns('ok')
      Beetle.config.redis_configuration_master_retry_timeout = 0.second
      Beetle.config.redis_configuration_master_retries       = 1
      RedisConfigurationServer.client.deduplication_store.redis_instances = [redis]
      RedisConfigurationServer.active_master = redis
      RedisConfigurationServer.find_active_master
      assert_equal redis, RedisConfigurationServer.active_master
    end

    test "find_active_master should finally give up to reach the current master after the max timeouts have been reached" do
      non_working_redis  = redis_stub('non-working-redis')
      non_working_redis.expects(:info).raises(Timeout::Error).twice
      working_redis      = redis_stub('working-redis')
      working_redis.expects(:info).returns("ok")

      Beetle.config.redis_configuration_master_retry_timeout   = 0.second
      Beetle.config.redis_configuration_master_retries         = 1
      RedisConfigurationServer.client.deduplication_store.redis_instances = [non_working_redis, working_redis]
      RedisConfigurationServer.active_master = non_working_redis
      RedisConfigurationServer.find_active_master
    end

    test "a forced change in find_active_master should start a reconfiguration run eve if there is a working redis" do
      working_redis_1 = redis_stub('working-redis_1', :info => "ok")
      working_redis_2 = redis_stub('working-redis_2', :info => "ok")
      RedisConfigurationServer.active_master = working_redis_1
      RedisConfigurationServer.client.deduplication_store.redis_instances = [working_redis_1, working_redis_2]
      RedisConfigurationServer.expects(:reconfigure).with(working_redis_2)
      RedisConfigurationServer.find_active_master(true)
    end

    test "clear active master should set the current master to nil" do
      RedisConfigurationServer.active_master = "snafu"
      RedisConfigurationServer.send(:clear_active_master)
      assert_nil RedisConfigurationServer.active_master
    end

    test "give master should return the current master" do
      RedisConfigurationServer.active_master = "foobar"
      assert_equal 'foobar', RedisConfigurationServer.give_master({:server_name => 'foo'})
    end

    test "give master should set an alive timestamp for the given server" do
      assert !RedisConfigurationServer.server_alive?('foo')
      RedisConfigurationServer.give_master({'server_name' => 'foo'})
      assert RedisConfigurationServer.server_alive?('foo')
    end

    test "servers that didnt ask for a server within the last 10 seconds are to be marked dead" do
      add_alive_server('bar')
      RedisConfigurationServer.alive_servers['bar'] = Time.now - 10.seconds
      assert !RedisConfigurationServer.server_alive?('bar')
    end
  end

  class RedisConfigurationServerReconfigurationTest < Test::Unit::TestCase

    def setup
      stub_redis_configuration_server_class
      EM.stubs(:add_timer)
    end

    test "the reconfigure method should publish the reconfigure message with the new master data" do
      redis_options = {'host' => 'foobar', 'port' => '1234'}
      new_master    = redis_stub('new_master', redis_options)
      RedisConfigurationServer.client.expects(:publish).with do |message_name, json|
        message_name == :reconfigure && ActiveSupport::JSON.decode(json) == redis_options
      end
      RedisConfigurationServer.reconfigure(new_master)
    end

    test "the reconfigure method should start the setup_reconfigured_check_timer" do
      new_master    = redis_stub('new_master')
      RedisConfigurationServer.expects(:setup_reconfigured_check_timer).with(new_master)
      RedisConfigurationServer.reconfigure(new_master)
    end

    test "the reconfigure check timer should setup a timer to check wether all clients have answered properly" do
      new_master    = redis_stub('new_master')
      RedisConfigurationServer.client.config.redis_configuration_reconfiguration_timeout = 12
      EM.expects(:add_timer).with(12).yields
      RedisConfigurationServer.expects(:check_reconfigured_answers)
      RedisConfigurationServer.send(:setup_reconfigured_check_timer, new_master)
    end
    
    test "the all_alive_servers_reconfigured? should return true if all clients have answered properly" do
      flunk      
    end

  end

end

