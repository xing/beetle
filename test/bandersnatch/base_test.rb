require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Bandersnatch
  class AMQPConfigTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(nil)
    end

    test "should load default config file" do
      assert_not_nil @bs.amqp_config
    end

    test "loading default config file should specify server localhost::5672" do
      assert_equal ["localhost:5672"], @bs.servers
    end

    test "default config should specify test and deadletter messages" do
      assert @bs.messages.include? "deadletter"
      assert @bs.messages.include? "test"
    end

    test "server should be initialized" do
      assert_equal @bs.servers.first, @bs.server
    end

    test "initially there should be no bunnies" do
      assert_equal({}, @bs.instance_variable_get("@bunnies"))
    end

    test "initially there should be no amqp connections" do
      assert_equal({}, @bs.instance_variable_get("@amqp_connections"))
    end

    test "initially there should be no instances of MQ" do
      assert_equal({}, @bs.instance_variable_get("@mqs"))
    end

    test "initially there should be no dead servers" do
      assert_equal({}, @bs.instance_variable_get("@dead_servers"))
    end

    test "initially we should not be in trace mode" do
      assert !@bs.instance_variable_get("@trace")
    end

    test "initially we should have no exchanges" do
      assert_equal({}, @bs.instance_variable_get("@exchanges"))
    end
  end

  class BandersnatchHandlerRegistrationTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(nil)
    end

    test "registering an exchange should store it in the configuration with symbolized option keys" do
      opts = {"durable" => true}
      @bs.register_exchange "some_exchange", opts
      assert_equal({:durable => true}, @bs.amqp_config["exchanges"]["some_exchange"])
    end

    test "registering a queue should store it in the configuration with symbolized option keys" do
      opts = {"durable" => true}
      @bs.register_queue "some_queue", opts
      assert_equal({:durable => true}, @bs.amqp_config["queues"]["some_queue"])
    end
  end

  class ServerManagementTest < Test::Unit::TestCase
    def setup
      @client = mock('client')
      @bs = Base.new(@client)
    end

    test "marking the current server as dead should add it to the dead servers hash and remove it from the active servers list" do
      @client.servers = ["localhost:1111", "localhost:2222"]
      @bs.set_current_server("localhost:2222")
      @bs.mark_server_dead
      assert_equal ["localhost:1111"], @bs.servers
      dead = @bs.instance_variable_get "@dead_servers"
      assert_equal ["localhost:2222"], dead.keys
      assert_kind_of Time, dead["localhost:2222"]
    end

    test "current_host should return the hostname of the current server" do
      @bs.server = "localhost:123"
      assert_equal "localhost", @bs.current_host
    end

    test "current_port should return the port of the current server as an integer" do
      @bs.server = "localhost:123"
      assert_equal 123, @bs.current_port
    end

    test "current_port should return the default rabbit port if server string does not contain a port" do
      @bs.server = "localhost"
      assert_equal 5672, @bs.current_port
    end

    test "set_current_server shoud set the current server" do
      @bs.set_current_server "xxx:123"
      assert_equal "xxx:123", @bs.server
    end

    test "select_next_server should cycle through the list of all servers" do
      @client.servers = ["a:1", "b:2"]
      @bs.set_current_server("a:1")
      @bs.select_next_server
      assert_equal "b:2", @bs.server
      @bs.select_next_server
      assert_equal "a:1", @bs.server
    end

    test "recycle_dead_servers should move servers from the dead server hash to the servers list only if the have been markd dead for longer than 10 seconds" do
      @@client.servers = ["a:1", "b:2"]
      @bs.set_current_server "a:1"
      @bs.mark_server_dead
      assert_equal ["b:2"], @bs.servers
      dead = @bs.instance_variable_get("@dead_servers")
      dead["a:1"] = 9.seconds.ago
      @bs.recycle_dead_servers
      assert_equal ["a:1"], dead.keys
      dead["a:1"] = 11.seconds.ago
      @bs.recycle_dead_servers
      assert_equal ["b:2", "a:1"], @bs.servers
      assert_equal({}, dead)
    end
  end
end