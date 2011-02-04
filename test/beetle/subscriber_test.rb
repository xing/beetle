require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class SubscriberTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @sub = client.send(:subscriber)
    end

    test "initially there should be no amqp connections" do
      assert_equal({}, @sub.instance_variable_get("@amqp_connections"))
    end

    test "initially there should be no instances of MQ" do
      assert_equal({}, @sub.instance_variable_get("@mqs"))
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
      expected_amqp_options = {
        :host => @sub.send(:current_host), :port => @sub.send(:current_port),
        :user => "guest", :pass => "guest", :vhost => "/"
      }
      AMQP.expects(:connect).with(expected_amqp_options).returns(m)
      # TODO: smarter way to test? what triggers the amqp_connection private method call?
      assert_equal m, @sub.send(:new_amqp_connection)
    end

    test "mq instances should be created for the current server if accessed" do
      @sub.expects(:amqp_connection).returns(11)
      mq_mock = mock('mq')
      mq_mock.expects(:prefetch).with(1).returns(42)
      MQ.expects(:new).with(11).returns(mq_mock)
      assert_equal 42, @sub.send(:mq)
      mqs = @sub.instance_variable_get("@mqs")
      assert_equal 42, mqs[@sub.server]
    end

    test "stop! should close all amqp connections and then stop the event loop" do
      connection1 = mock('con1')
      connection1.expects(:close).yields
      connection2 = mock('con2')
      connection2.expects(:close).yields
      @sub.instance_variable_set "@amqp_connections", [["server1", connection1], ["server2",connection2]]
      EM.expects(:stop_event_loop)
      @sub.send(:stop!)
    end

  end

  class AdditionalSubscriptionServersTest < Test::Unit::TestCase
    def setup
      @config = Configuration.new
      @config.additional_subscription_servers = "localhost:1234"
      @client = Client.new(@config)
      @sub = @client.send(:subscriber)
    end

    test "subscribers server list should contain addtional subcription hosts" do
      assert_equal ["localhost:5672", "localhost:1234"], @sub.servers
    end
  end

  class SubscriberQueueManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @sub.send(:queues))
      assert !@sub.send(:queues)["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @client.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange", "key" => "haha.#")
      @sub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("MQ")
      m.expects(:queue).with("some_queue", :durable => true, :passive => false, :auto_delete => false, :exclusive => false).returns(q)
      @sub.expects(:mq).returns(m)

      @sub.send(:queue, "some_queue")
      assert_equal q, @sub.send(:queues)["some_queue"]
    end

    test "binding queues should iterate over all servers" do
      s = sequence("binding")
      @client.register_queue(:x)
      @client.register_queue(:y)
      @client.register_handler(%w(x y)){}
      @sub.servers = %w(a b)
      @sub.expects(:set_current_server).with("a").in_sequence(s)
      @sub.expects(:queue).with("x").in_sequence(s)
      @sub.expects(:queue).with("y").in_sequence(s)
      @sub.expects(:set_current_server).with("b").in_sequence(s)
      @sub.expects(:queue).with("x").in_sequence(s)
      @sub.expects(:queue).with("y").in_sequence(s)
      @sub.send(:bind_queues, %W(x y))
    end

    test "should not try to bind a queue for an exchange which has no queue" do
      @client.register_message(:without_queue)
      assert_equal [], @sub.send(:queues_for_exchanges, ["without_queue"])
    end
  end

  class SubscriberExchangeManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @sub.send(:exchanges))
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      @client.register_exchange("some_exchange", "type" => "topic", "durable" => true)
      m = mock("AMQP")
      m.expects(:topic).with("some_exchange", :durable => true).returns(42)
      @sub.expects(:mq).returns(m)
      ex = @sub.send(:exchange, "some_exchange")
      assert @sub.send(:exchanges).include?("some_exchange")
      ex2 = @sub.send(:exchange, "some_exchange")
      assert_equal ex2, ex
    end

    test "should create exchanges for all exchanges passed to create_exchanges, for all servers" do
      @sub.servers = %w(x y)
      @client.register_queue(:donald, :exchange => 'duck')
      @client.register_queue(:mickey)
      @client.register_queue(:mouse, :exchange => 'mickey')

      exchange_creation = sequence("exchange creation")
      @sub.expects(:set_current_server).with('x').in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("duck", anything).in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("mickey", anything).in_sequence(exchange_creation)
      @sub.expects(:set_current_server).with('y', anything).in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("duck", anything).in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("mickey", anything).in_sequence(exchange_creation)
      @sub.send(:create_exchanges, %w(duck mickey))
    end
  end

  class CallBackExecutionTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @queue = "somequeue"
      client.register_queue(@queue)
      @sub = client.send(:subscriber)
      @exception = Exception.new "murks"
      @handler = Handler.create(lambda{|*args| raise @exception})
      @callback = @sub.send(:create_subscription_callback, "my myessage", @queue, @handler, :exceptions => 1)
    end

    test "exceptions raised from message processing should be ignored" do
      header = header_with_params({})
      Message.any_instance.expects(:process).raises(Exception.new("don't worry"))
      assert_nothing_raised { @callback.call(header, 'foo') }
    end

    test "should call reject on the message header when processing the handler returns true on recover?" do
      header = header_with_params({})
      result = mock("result")
      result.expects(:reject?).returns(true)
      Message.any_instance.expects(:process).returns(result)
      @sub.expects(:sleep).with(1)
      header.expects(:reject).with(:requeue => true)
      @callback.call(header, 'foo')
    end

    test "should sent a reply with status OK if the message reply_to header is set and processing the handler succeeds" do
      header = header_with_params(:reply_to => "tmp-queue")
      result = RC::OK
      Message.any_instance.expects(:process).returns(result)
      Message.any_instance.expects(:handler_result).returns("response-data")
      mq = mock("MQ")
      @sub.expects(:mq).with(@sub.server).returns(mq)
      exchange = mock("exchange")
      exchange.expects(:publish).with("response-data", :headers => {:status => "OK"})
      MQ::Exchange.expects(:new).with(mq, :direct, "", :key => "tmp-queue").returns(exchange)
      @callback.call(header, 'foo')
    end

    test "should sent a reply with status FAILED if the message reply_to header is set and processing the handler fails" do
      header = header_with_params(:reply_to => "tmp-queue")
      result = RC::AttemptsLimitReached
      Message.any_instance.expects(:process).returns(result)
      Message.any_instance.expects(:handler_result).returns(nil)
      mq = mock("MQ")
      @sub.expects(:mq).with(@sub.server).returns(mq)
      exchange = mock("exchange")
      exchange.expects(:publish).with("", :headers => {:status => "FAILED"})
      MQ::Exchange.expects(:new).with(mq, :direct, "", :key => "tmp-queue").returns(exchange)
      @callback.call(header, 'foo')
    end

  end

  class SubscriptionTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
    end

    test "subscribe should create subscriptions on all queues for all servers" do
      @sub.servers << "localhost:7777"
      @client.register_message(:a)
      @client.register_message(:b)
      @client.register_queue(:a)
      @client.register_queue(:b)
      @client.register_handler(%W(a b)){}
      @sub.expects(:subscribe).with("a").times(2)
      @sub.expects(:subscribe).with("b").times(2)
      @sub.send(:subscribe_queues, %W(a b))
    end

    test "subscribe should subscribe with a subscription callback created from the registered block" do
      @client.register_queue(:some_queue, :exchange => "some_exchange", :key => "some_key")
      server = @sub.server
      header = header_with_params({})
      header.expects(:ack)
      block_called = false
      proc = lambda do |m|
        block_called = true
        assert_equal header, m.header
        assert_equal "foo", m.data
        assert_equal server, m.server
      end
      @sub.register_handler("some_queue", &proc)
      q = mock("QUEUE")
      q.expects(:subscribe).with({:ack => true, :key => "#"}).yields(header, "foo")
      @sub.expects(:queues).returns({"some_queue" => q})
      @sub.send(:subscribe, "some_queue")
      assert block_called
    end

    test "subscribe should fail if no handler exists for given message" do
      assert_raises(Error){ @sub.send(:subscribe, "some_queue") }
    end

    test "listeninging on queues should use eventmachine. create exchanges. bind queues. install subscribers. and yield." do
      @client.register_exchange(:an_exchange)
      @client.register_queue(:a_queue, :exchange => :an_exchange)
      @client.register_message(:a_message, :key => "foo", :exchange => :an_exchange)

      EM.expects(:run).yields
      @sub.expects(:create_exchanges).with(["an_exchange"])
      @sub.expects(:bind_queues).with(["a_queue"])
      @sub.expects(:subscribe_queues).with(["a_queue"])
      @sub.listen_queues(["a_queue"]) {}
    end
  end

  class HandlersTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
    end

    test "initially we should have no handlers" do
      assert_equal({}, @sub.instance_variable_get("@handlers"))
    end

    test "registering a handler for a queue should store it in the configuration with symbolized option keys" do
      opts = {"ack" => true}
      @sub.register_handler("some_queue", opts){ |*args| 42 }
      opts, block = @sub.instance_variable_get("@handlers")["some_queue"]
      assert_equal({:ack => true}, opts)
      assert_equal 42, block.call(1)
    end

  end

end
