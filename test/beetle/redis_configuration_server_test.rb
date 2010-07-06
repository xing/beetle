require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationServerClientInvalidatedMethodTest < Test::Unit::TestCase
    test "should ignore outdated client_invalidated messages" do
      Beetle.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      server = RedisConfigurationServer.new

      server.instance_variable_set(:@current_token, 2)
      server.client_invalidated("id" => "rc-client-1", "token" => 2)
      old_token = 1.minute.ago.to_f
      server.client_invalidated("id" => "rc-client-2", "token" => 1)

      assert_equal(["rc-client-1"].to_set, server.instance_variable_get(:@client_invalidated_ids_received))
    end
  end

  class RedisConfigurationServerInvalidationMessageTokenTest < Test::Unit::TestCase
    test "should initialize the invalidation message token to not reuse old tokens" do
      server = RedisConfigurationServer.new
      sleep 0.1
      server_2 = RedisConfigurationServer.new
      assert server_2.current_token > server.current_token
    end
  end

  class RedisConfigurationServerInvalidationTest < Test::Unit::TestCase
    def setup
      Beetle.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      @server = RedisConfigurationServer.new
      @server.stubs(:redis_master).returns(stub('redis stub', :server => 'stubbed_server', :available? => false))
      @server.send(:beetle_client).stubs(:listen).yields
      @server.send(:beetle_client).stubs(:publish)
      EM::Timer.stubs(:new).returns(true)
      EventMachine.stubs(:add_periodic_timer).yields
    end

    test "should pause watching of the redis server" do
      EM.stubs(:add_periodic_timer).returns(stub("timer", :cancel => true))
      @server.start
      assert !@server.paused?
      @server.master_unavailable
      assert @server.paused?
    end

    test "should setup an invalidation timeout" do
      EM::Timer.expects(:new).yields
      @server.expects(:cancel_invalidation)
      @server.master_unavailable
    end

    test "should continue watching after the invalidation timeout has expired" do
      EM::Timer.expects(:new).yields
      @server.master_unavailable
      assert !@server.paused?
    end
  end

  class RedisConfigurationServerInitialConfigurationTest < Test::Unit::TestCase
    def setup
      EM::Timer.stubs(:new).returns(true)
      EventMachine.stubs(:add_periodic_timer).yields
      client = Client.new(Configuration.new)
      client.stubs(:listen).yields
      client.stubs(:publish)
      client.config.redis_server = "stubbed_master:0"
      client.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      @server = RedisConfigurationServer.new
      @server.stubs(:beetle_client).returns(client)
    end

    test "autoconfiguration should succeed if a valid slave/master pair can be found" do
      redis_master = stub("redis master", :server => 'stubbed_master:0', :available? => true, :master? => true)
      redis_slave  = stub("redis slave",  :server => 'stubbed_slave:0',  :available? => true, :master? => false)
      @server.stubs(:redis_instances).returns([redis_master, redis_slave])
      assert_equal redis_master, @server.send(:determine_initial_redis_master)
    end

    test "autoconfiguration should fallback to read the master file if a valid slave/master pair can't be found" do
      redis_master = stub("redis master", :server => 'stubbed_master:0', :available? => true, :master? => true)
      redis_slave  = stub("redis slave",  :server => 'stubbed_slave:0',  :available? => true, :master? => true)
      @server.stubs(:redis_instances).returns([redis_master, redis_slave])
      @server.expects(:redis_master_from_master_file)
      @server.send(:determine_initial_redis_master)
    end

  end
end
