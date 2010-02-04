require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Bandersnatch
  class SubscriberTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @sub = Subscriber.new(client)
    end

    test "initially there should be no amqp connections" do
      assert_equal({}, @sub.instance_variable_get("@amqp_connections"))
    end

    test "initially there should be no instances of MQ" do
      assert_equal({}, @sub.instance_variable_get("@mqs"))
    end

    test "initially we should not be in trace mode" do
      assert !@sub.trace
    end

    test "acccessing an amq_connection for a server which doesn't have one should create it and associate it with the server" do
      @sub.expects(:new_amqp_connection).returns(42)
      # TODO: smarter way to test? what triggers the amqp_connection private method call?
      assert_equal 42, @sub.send(:amqp_connection)
      connections = @sub.instance_variable_get("@amqp_connections")
      assert_equal 42, connections[@sub.server]
    end

    test "new amqp connections should be created using current host and port" do
      m = mock("dummy")
      AMQP.expects(:connect).with(:host => @sub.send(:current_host), :port => @sub.send(:current_port)).returns(m)
      # TODO: smarter way to test? what triggers the amqp_connection private method call?
      assert_equal m, @sub.send(:new_amqp_connection)
    end

    test "mq instances should be created for the current server if accessed" do
      @sub.expects(:amqp_connection).returns(11)
      MQ.expects(:new).with(11).returns(42)
      assert_equal 42, @sub.send(:mq)
      mqs = @sub.instance_variable_get("@mqs")
      assert_equal 42, mqs[@sub.server]
    end
  end

  class SubscriberQueueManagementTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @sub = Subscriber.new(client)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @sub.send(:queues))
      assert !@sub.send(:queues)["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @sub.instance_variable_get("@amqp_config")["queues"].merge!({"some_queue" => {"durable" => true, "exchange" => "some_exchange", "key" => "haha.#"}})
      @sub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("MQ")
      m.expects(:queue).with("some_queue", :durable => true).returns(q)
      @sub.expects(:mq).returns(m)

      @sub.send(:bind_queue, "some_queue")
      assert_equal q, @sub.send(:queues)["some_queue"]
    end
  end

  class SubscriberExchangeManagementTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @sub = Subscriber.new(client)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @sub.send(:exchanges_for_current_server))
      assert !@sub.send(:exchange_exists?, "some_message")
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      @sub.instance_variable_get("@amqp_config")["exchanges"].merge!({ "some_exchange" => { "type" => "topic", "durable" => true } })
      m = mock("AMQP")
      m.expects(:topic).with("some_exchange", :durable => true).returns(42)
      @sub.expects(:mq).returns(m)
      ex = @sub.send(:exchange, "some_exchange")
      assert @sub.send(:exchange_exists?, "some_exchange")
      ex2 = @sub.send(:exchange, "some_exchange")
      assert_equal ex2, ex
    end
  end

  class TimerTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @sub = Subscriber.new(client)
      @handler = mock("handler")
      @queue = 'somequeue'
      @callback = @sub.send(:create_subscription_callback, 'servername', @queue, @handler)
    end

    test "the internal timer should get refreshed for every failed message processing" do
      body = Message.encode("my message")
      header = mock("header")
      message = Message.new(@queue, header, body)
      Message.any_instance.expects(:process).raises(Exception)
      timer = mock("timer")

      timer.expects(:cancel).once
      EM::Timer.expects(:new).twice.returns(timer)
      @callback.call(header, body)
      @callback.call(header, body)
    end
  end

  class SubscriptionTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @sub = Subscriber.new(client)
    end

    test "subscribe should create subscriptions for all servers" do
      @sub.servers << "localhost:7777"
      @sub.messages = {"a" => 1, "b" => 2}
      @sub.expects(:subscribe_message).with("a").times(2)
      @sub.expects(:subscribe_message).with("b").times(2)
      @sub.send(:subscribe)
    end

    test "subscribe_message should subscribe with a subscription callback created from the registered block" do
      opts = {"ack" => true, "key" =>"some_key"}
      server = @sub.server
      header = mock("header")
      header.expects(:ack)
      block_called = false
      proc = lambda do |m|
        block_called = true
        assert_equal header, m.header
        assert_equal "data", m.data
        assert_equal server, m.server
      end
      @sub.register_handler("some_message", opts, &proc)
      q = mock("QUEUE")
      q.expects(:subscribe).with({:ack => true, :key => "some_key.#"}).yields(header, Message.encode("data"))
      @sub.expects(:queues).returns({"some_message" => q})
      @sub.send(:subscribe_message, "some_message")
      assert block_called
    end

    test "subscribe should fail if no handler exists for given message" do
      assert_raises(Error){ @sub.send(:subscribe_message, "some_message") }
    end

    test "listening should use eventmachine. create exchanges. bind queues. install subscribers." do
      EM.expects(:run).yields
      @sub.expects(:create_exchanges).with(["a"])
      @sub.expects(:bind_queues).with(["a"])
      @sub.expects(:subscribe)
      @sub.listen(["a"]) {}
    end
  end

  class HandlersTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @sub = Subscriber.new(client)
    end

    test "initially we should have no handlers" do
      assert_equal({}, @sub.instance_variable_get("@handlers"))
    end

    test "registering a handler for a message should store it in the configuration with symbolized option keys" do
      opts = {"ack" => true}
      @sub.register_handler("some_message", opts){ |*args| 42 }
      opts, block = @sub.instance_variable_get("@handlers")["some_message"].first
      assert_equal({:ack => true}, opts)
      assert_equal 42, block.call
    end

    test "should allow registration of multiple handlers for a message" do
      opts = {}
      @sub.register_handler("a message", { :queue => "queue_1" } ) { |*args| "handler 1" }
      @sub.register_handler("a message", { :queue => "queue_2" }) { |*args| "handler 2" }
      handlers = @sub.instance_variable_get("@handlers")["a message"]
      handler1, handler2 = handlers
      assert_equal 2, handlers.size
      assert_equal "queue_1", handler1[0][:queue]
      assert_equal "handler 1", handler1[1].call
      assert_equal "queue_2", handler2[0][:queue]
      assert_equal "handler 2", handler2[1].call
    end
  end
end
