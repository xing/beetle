require File.expand_path(File.dirname(__FILE__) + '/test_helper')


module Bandersnatch
  class AMQPConfigTest < Test::Unit::TestCase
    def setup
      @bs = Base.new
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

    test "initially we should have no handlers" do
      assert_equal({}, @bs.instance_variable_get("@handlers"))
    end
  end

  class BandersnatchHandlerRegistrationTest < Test::Unit::TestCase
    def setup
      @bs = Base.new
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

    test "registering a handler for a message should store it in the configuration with symbolized option keys" do
      opts = {"ack" => true}
      @bs.register_handler("some_message", opts){ |*args| 42 }
      opts, block = @bs.instance_variable_get("@handlers")["some_message"].first
      assert_equal({:ack => true}, opts)
      assert_equal 42, block.call
    end

    test "should allow registration of multiple handlers for a message" do
      opts = {}
      @bs.register_handler("a message", { :queue => "queue_1" } ) { |*args| "handler 1" }
      @bs.register_handler("a message", { :queue => "queue_2" }) { |*args| "handler 2" }
      handlers = @bs.instance_variable_get("@handlers")["a message"]
      handler1, handler2 = handlers
      assert_equal 2, handlers.size
      assert_equal "queue_1", handler1[0][:queue]
      assert_equal "handler 1", handler1[1].call
      assert_equal "queue_2", handler2[0][:queue]
      assert_equal "handler 2", handler2[1].call
    end
  end


  class SubscriptionTest < Test::Unit::TestCase
    def setup
      @bs = Base.new
    end

    test "subscribe should create subscriptions for all servers" do
      @bs.servers << "localhost:7777"
      @bs.messages = {"a" => 1, "b" => 2}
      @bs.expects(:subscribe_message).with("a").times(2)
      @bs.expects(:subscribe_message).with("b").times(2)
      @bs.subscribe
    end

    test "subscribe_message should subscribe with a subscription callback created from the registered block" do
      opts = {"ack" => true, "key" =>"some_key"}
      server = @bs.server
      header = mock("header")
      header.expects(:ack)
      block_called = false
      proc = lambda do |m|
        block_called = true
        assert_equal header, m.header
        assert_equal "data", m.data
        assert_equal server, m.server
        assert_nil m.uuid
      end
      @bs.register_handler("some_message", opts, &proc)
      q = mock("QUEUE")
      q.expects(:subscribe).with({:ack => true, :key => "some_key.#"}).yields(header, Message.encode("data"))
      @bs.expects(:queues).returns({"some_message" => q})
      @bs.subscribe_message("some_message")
      assert block_called
    end

    test "subscribe should fail if no handler exists for given message" do
      assert_raises(Error){ @bs.subscribe_message("some_message") }
    end

    test "listening should use eventmachine. create exchanges. bind queues. install subscribers." do
      EM.expects(:run).yields
      @bs.expects(:create_exchanges).with(["a"])
      @bs.expects(:bind_queues).with(["a"])
      @bs.expects(:subscribe)
      @bs.listen(["a"]) {}
    end

  end

  class ServerManagementTest < Test::Unit::TestCase
    def setup
      @bs = Base.new
    end

    test "marking the current server as dead should add it to the dead servers hash and remove it from the active servers list" do
      @bs.servers = ["localhost:1111", "localhost:2222"]
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
      @bs.servers = ["a:1", "b:2"]
      @bs.set_current_server("a:1")
      @bs.select_next_server
      assert_equal "b:2", @bs.server
      @bs.select_next_server
      assert_equal "a:1", @bs.server
    end

    test "recycle_dead_servers should move servers from the dead server hash to the servers list only if the have been markd dead for longer than 10 seconds" do
      @bs.servers = ["a:1", "b:2"]
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

  class DeDuplificationTest < Test::Unit::TestCase
    def setup
      @bs = Base.new
      @handler = mock("handler")
      @queue = 'somequeue'
      @callback = @bs.create_subscription_callback('servername', @queue, @handler)
    end

    test 'a message handler should call the callback if the message id is not already in the database' do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("server", header, body)

      Message.any_instance.expects(:insert_id).with(@queue).returns(true)
      @handler.expects(:call)
      @callback.call(header, body)
    end

    test "a message handler should not call the callback if the message id is already in the database" do
      body = Message.encode("my message", :with_uuid => true)
      header = mock("header")
      message = Message.new("server", header, body)
      header.expects(:ack)

      @handler.expects(:call).never
      Message.any_instance.expects(:insert_id).with(@queue).returns(false)
      @callback.call(header, body)
    end

    test "the message callback should not get called and the message should not be ack'ed if the db check fails" do
      body = Message.encode("my message", :with_uuid => true)
      header = mock("header")
      message = Message.new("server", header, body)

      header.expects(:ack).never
      Message.any_instance.expects(:insert_id).raises(Exception)
      EM.expects(:add_timer).once
      @callback.call(header, body)
    end

    test "the internal timer should get refreshed for every failing db check" do
      body = Message.encode("my message", :with_uuid => true)
      header = mock("header")
      message = Message.new("server", header, body)
      Message.any_instance.expects(:insert_id).raises(Exception)
      timer = mock("timer")

      timer.expects(:cancel).once
      EM::Timer.expects(:new).twice.returns(timer)
      @callback.call(header, body)
      @callback.call(header, body)
    end

    test "expired messages should be silently dropped without inserting a uuid into the database" do
      body = Message.encode("my message", :ttl => -1)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("server", header, body)

      @handler.expects(:call).never
      Message.any_instance.expects(:insert_id).never
      @callback.call(header, body)
    end
  end
end