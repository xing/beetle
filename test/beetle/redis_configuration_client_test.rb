require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationClientTest < MiniTest::Unit::TestCase
    def setup
      Beetle.config.redis_servers = "redis:0,redis:1"
      @client = RedisConfigurationClient.new
      @client.stubs(:touch_master_file)
      @client.stubs(:verify_redis_master_file_string)
    end

    test "should send a client_started message when started" do
      @client.stubs(:clear_redis_master_file)
      @client.beetle.expects(:publish).with(:client_started, {:id => @client.id}.to_json)
      Client.any_instance.stubs(:listen)
      @client.start
    end

    test "should install a periodic timer which sends a heartbeat message" do
      @client.stubs(:clear_redis_master_file)
      @client.beetle.expects(:publish).with(:client_started, {:id => @client.id}.to_json)
      @client.beetle.expects(:listen).yields
      EventMachine.expects(:add_periodic_timer).with(Beetle.config.redis_failover_client_heartbeat_interval).yields
      @client.beetle.expects(:publish).with(:heartbeat, {:id => @client.id}.to_json)
      @client.start
    end

    test "config should return the beetle config" do
      assert_equal Beetle.config, @client.config
    end

    test "ping message should answer with pong" do
      @client.expects(:pong!)
      @client.ping("token" => 1)
    end

    test "pong should publish a pong message" do
      @client.beetle.expects(:publish)
      @client.send(:pong!)
    end

    test "invalidation should send an invalidation message and clear the redis master file" do
      @client.expects(:clear_redis_master_file)
      @client.beetle.expects(:publish).with(:client_invalidated, anything)
      @client.send(:invalidate!)
    end

    test "should ignore outdated invalidate messages" do
      new_payload = {"token" => 2}
      old_payload = {"token" => 1}

      @client.expects(:invalidate!).once

      @client.invalidate(new_payload)
      @client.invalidate(old_payload)
    end

    test "should ignore invalidate messages when current master is still a master" do
      @client.instance_variable_set :@current_master, stub(:master? => true)
      @client.expects(:invalidate!).never
      @client.invalidate("token" => 1)
    end

    test "should ignore outdated reconfigure messages" do
      new_payload = {"token" => 2, "server" => "master:2"}
      old_payload = {"token" => 1, "server" => "master:1"}
      @client.stubs(:read_redis_master_file).returns("")

      @client.expects(:write_redis_master_file).once

      @client.reconfigure(new_payload)
      @client.reconfigure(old_payload)
    end

    test "should clear redis master file if redis from master file is slave" do
      @client.stubs(:redis_master_from_master_file).returns(stub(:master? => false))
      Beetle::Client.any_instance.stubs(:publish)
      @client.expects(:clear_redis_master_file)
      @client.expects(:client_started!)
      Client.any_instance.stubs(:listen)
      @client.start
    end

    test "should clear redis master file if redis from master file is not available" do
      @client.stubs(:redis_master_from_master_file).returns(nil)
      Beetle::Client.any_instance.stubs(:publish)
      @client.expects(:clear_redis_master_file)
      @client.expects(:client_started!)
      Client.any_instance.stubs(:listen)
      @client.start
    end

    test "the dispatcher should just forward messages to the client" do
      dispatcher_class = RedisConfigurationClient.class_eval "MessageDispatcher"
      dispatcher_class.configuration_client = @client
      dispatcher = dispatcher_class.new
      payload = {"token" => 1}
      dispatcher.stubs(:message).returns(stub(:data => payload.to_json, :header => stub(:routing_key=> "ping")))
      @client.expects(:ping).with(payload)
      dispatcher.send(:process)
    end

    test "determine_initial_master should return nil if there is no file" do
      @client.expects(:master_file_exists?).returns(false)
      assert_nil @client.send(:determine_initial_master)
      assert_nil @client.current_master
    end

    test "determine_initial_master should instantiate a new redis if there is a file with content" do
      @client.expects(:master_file_exists?).returns(true)
      @client.expects(:read_redis_master_file).returns(ENV["REDIS_SERVER"])
      master = @client.send(:determine_initial_master)
      assert_equal "master", master.role
      assert_equal master, @client.current_master
    end

  end
end
