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
      @server.instance_variable_set(:@redis_master, stub('redis stub', :server => 'stubbed_server', :available? => false))
      @server.send(:beetle_client).stubs(:listen).yields
      @server.send(:beetle_client).stubs(:publish)
      EM::Timer.stubs(:new).returns(true)
      EventMachine.stubs(:add_periodic_timer).yields
    end

    test "should pause watching of the redis master when it becomes unavailable" do
      @server.expects(:determine_initial_redis_master)
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

  class RedisConfigurationServerInitialRedisMasterDeterminationTest < Test::Unit::TestCase
    def setup
      EM::Timer.stubs(:new).returns(true)
      EventMachine.stubs(:add_periodic_timer).yields
      @client = Client.new(Configuration.new)
      @client.stubs(:listen).yields
      @client.stubs(:publish)
      @client.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      @server = RedisConfigurationServer.new
      @server.stubs(:beetle_client).returns(@client)
      @server.stubs(:write_redis_master_file)
      @redis_master  = build_master_redis_stub
      @redis_slave   = build_slave_redis_stub
    end

    test "should not try to auto-detect if the master file contains a server string" do
      @server.stubs(:redis_instances).returns([@redis_master, @redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(@redis_master, @redis_slave))
      @server.expects(:master_file_exists?).returns(true)
      @server.stubs(:read_redis_master_file).returns("foobar:0000")

      @server.expects(:auto_detect_master).never
      @server.expects(:redis_master_from_master_file).returns(@redis_master)
      @server.send(:determine_initial_redis_master)
    end

    test "should try to auto-detect if the master file is empty" do
      @server.expects(:master_file_exists?).returns(true)
      @server.stubs(:redis_instances).returns([@redis_master, @redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(@redis_master, @redis_slave))
      @server.stubs(:read_redis_master_file).returns("")

      @server.expects(:auto_detect_master).returns(@redis_master)
      @server.send(:determine_initial_redis_master)
    end

    test "should try to auto-detect if the master file is not present" do
      @server.expects(:master_file_exists?).returns(false)
      @server.stubs(:redis_instances).returns([@redis_master, @redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(@redis_master, @redis_slave))

      @server.expects(:auto_detect_master).returns(@redis_master)
      @server.send(:determine_initial_redis_master)
    end

    test "should use redis master from successful auto-detection" do
      @server.expects(:master_file_exists?).returns(false)
      @server.stubs(:redis_instances).returns([@redis_master, @redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(@redis_master, @redis_slave))

      @server.expects(:write_redis_master_file).with(@redis_master.server)
      @server.send(:determine_initial_redis_master)
      assert_equal @redis_master, @server.redis_master
    end

    test "should use redis master if master in file is the only master" do
      @server.stubs(:redis_instances).returns([@redis_master, @redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(@redis_master, @redis_slave))
      @server.expects(:master_file_exists?).returns(true)
      @server.stubs(:redis_master_from_master_file).returns(@redis_master)

      @server.send(:determine_initial_redis_master)
      assert_equal @redis_master, @server.redis_master
    end

    test "should start master switch if master in file is slave" do
      @server.stubs(:redis_instances).returns([@redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(@redis_slave))
      @server.expects(:master_file_exists?).returns(true)
      @server.stubs(:redis_master_from_master_file).returns(@redis_slave)

      @server.expects(:master_unavailable)
      @server.send(:determine_initial_redis_master)
    end

    test "should use master from master file if multiple masters are available" do
      redis_master2 = build_master_redis_stub
      @server.stubs(:redis_instances).returns([@redis_master, redis_master2])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(@redis_master, redis_master2))
      @server.expects(:master_file_exists?).returns(true)
      @server.stubs(:redis_master_from_master_file).returns(@redis_master)

      @server.send(:determine_initial_redis_master)
      assert_equal @redis_master, @server.redis_master
    end

    test "should start master switch if master in file is not available" do
      not_available_redis_master = build_unknown_redis_stub
      @server.stubs(:redis_instances).returns([not_available_redis_master, @redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(not_available_redis_master, @redis_slave))
      @server.expects(:master_file_exists?).returns(true)
      @server.stubs(:redis_master_from_master_file).returns(not_available_redis_master)
      
      @server.expects(:master_unavailable)
      @server.send(:determine_initial_redis_master)
    end

    test "should raise an exception if both master file and auto-detection fails" do
      not_available_redis_master = build_unknown_redis_stub
      not_available_redis_slave  = build_unknown_redis_stub
      @server.stubs(:redis_instances).returns([not_available_redis_master, not_available_redis_slave])
      @server.instance_variable_set(:@redis_server_info, build_redis_server_info(not_available_redis_master, not_available_redis_slave))
      @server.expects(:master_file_exists?).returns(true)
      @server.expects(:read_redis_master_file).returns("")
      @server.expects(:auto_detect_master).returns(nil)

      assert_raises Beetle::NoRedisMaster do
        @server.send(:determine_initial_redis_master)
      end
    end

    private

    def build_master_redis_stub
      stub("redis master", :server => "stubbed_master:0", :available? => true, :master? => true, :slave? => false, :role => "master")
    end

    def build_slave_redis_stub
      stub("redis slave", :server => "stubbed_slave:0",  :available? => true, :master? => false, :slave? => true, :role => "slave")
    end
    
    def build_unknown_redis_stub
      stub("redis unknown", :server => "stubbed_unknown:0",  :available? => false, :master? => false, :slave? => false, :role => "unknown")
    end
    
    def build_redis_server_info(*redis_instances)
      redis_instances.inject({"master" => [], "slave" => [], "unknown" => []}){|memo, redis| memo[redis.role] << redis; memo }
    end
  end
end
