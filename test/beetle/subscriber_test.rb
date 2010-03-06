require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
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
      mq_mock = mock('mq')
      mq_mock.expects(:prefetch).with(1).returns(42)
      MQ.expects(:new).with(11).returns(mq_mock)
      assert_equal 42, @sub.send(:mq)
      mqs = @sub.instance_variable_get("@mqs")
      assert_equal 42, mqs[@sub.server]
    end

    test "stop! should stop the event loop" do
      EM.expects(:stop_event_loop)
      @sub.send(:stop!)
    end

  end

  class SubscriberQueueManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @sub = Subscriber.new(@client)
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
      m.expects(:queue).with("some_queue", :durable => true, :passive => false).returns(q)
      @sub.expects(:mq).returns(m)

      @sub.send(:queue, "some_queue")
      assert_equal q, @sub.send(:queues)["some_queue"]
    end

    test "binding queues should iterate over all servers" do
      s = sequence("binding")
      @sub.servers = %w(a b)
      @sub.expects(:set_current_server).with("a").in_sequence(s)
      @sub.expects(:queues_with_handlers).with(["test"]).returns(["testa"]).in_sequence(s)
      @sub.expects(:queue).with("testa").in_sequence(s)
      @sub.expects(:set_current_server).with("b").in_sequence(s)
      @sub.expects(:queues_with_handlers).with(["test"]).returns(["testb"]).in_sequence(s)
      @sub.expects(:queue).with("testb").in_sequence(s)
      @sub.send(:bind_queues, ["test"])
    end

    test "queues with handlers should return all queues to which handlers have been bound" do
      @sub.instance_variable_set(:@handlers, {"test" => [ [{:queue => "qa"}, 0], [{}, 1] ]})
      assert_equal ["qa", "test" ], @sub.send(:queues_with_handlers, ["test"]).sort
    end
  end

  class SubscriberExchangeManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @sub = Subscriber.new(@client)
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

    test "should create exchanges for all messages passed to create_exchanges, for all servers" do
      @sub.servers = %w(x y)
      messages = %w(a b)
      @client.register_exchange("unused")
      @client.register_queue('donald', :exchange => 'margot')
      @client.register_queue('mickey')
      @client.register_queue('mouse', :exchange => 'mickey')
      @client.register_message('a', :queue => 'donald')
      @client.register_message('b', :queue => 'mickey')
      @client.register_message('c', :queue => 'mouse')

      exchange_creation = sequence("exchange creation")
      @sub.expects(:set_current_server).with('x').in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("margot", anything).in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("mickey", anything).in_sequence(exchange_creation)
      @sub.expects(:set_current_server).with('y', anything).in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("margot", anything).in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("mickey", anything).in_sequence(exchange_creation)
      @sub.expects(:create_exchange!).with("unused").never
      @sub.send(:create_exchanges, messages)
    end
  end

  class CallBackExecutionTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @queue = "somequeue"
      client.register_queue(@queue)
      @sub = Subscriber.new(client)
      @exception = Exception.new "murks"
      @handler = Handler.create(lambda{|*args| raise @exception})
      @callback = @sub.send(:create_subscription_callback, "my myessage", @queue, @handler, {:exceptions => 4, :attempts => 4})
    end

    test "exceptions raised from message processing should be ignored" do
      header = header_with_params({})
      Message.any_instance.expects(:process).raises(Exception.new)
      assert_nothing_raised { @callback.call(header, 'foo') }
    end

    test "should call recover on the server when processing the handler returns true on recover?" do
      header = header_with_params({})
      result = mock("result")
      result.expects(:recover?).returns(true)
      Message.any_instance.expects(:process).returns(result)
      @sub.expects(:sleep).with(1)
      mq = mock("MQ")
      mq.expects(:recover)
      @sub.expects(:mq).with(@sub.server).returns(mq)
      @callback.call(header, 'foo')
    end
  end

  class SubscriptionTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @sub = Subscriber.new(@client)
    end

    test "subscribe should create subscriptions for all servers" do
      @sub.servers << "localhost:7777"
      @client.messages.clear
      @client.register_queue("a")
      @client.register_message("a")
      @client.register_message("b", :queue => "a")
      @sub.expects(:subscribe_message).with("a").times(2)
      @sub.expects(:subscribe_message).with("b").times(2)
      @sub.send(:subscribe, %W(a b))
    end

    test "subscribe_message should subscribe with a subscription callback created from the registered block" do
      @client.register_queue("some_queue")
      @client.register_message("some_message", :queue => "some_queue", :key => "some_key")
      server = @sub.server
      header = header_with_params({})
      header.expects(:ack)
      block_called = false
      proc = lambda do |m|
        block_called = true
        assert_equal header, m.header
        assert_equal "data", m.data
        assert_equal server, m.server
      end
      @sub.register_handler("some_message", {}, &proc)
      q = mock("QUEUE")
      q.expects(:subscribe).with({:ack => true, :key => "#"}).yields(header, 'foo')
      @sub.expects(:queues).returns({"some_queue" => q})
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
      assert_equal 42, block.call(1)
    end

    test "should allow registration of multiple handlers for a message" do
      opts = {}
      @sub.register_handler("a message", :queue => "queue_1") { |*args| "handler 1" }
      @sub.register_handler("a message", :queue => "queue_2") { |*args| "handler 2" }
      handlers = @sub.instance_variable_get("@handlers")["a message"]
      handler1, handler2 = handlers
      assert_equal 2, handlers.size
      assert_equal "queue_1", handler1[0][:queue]
      assert_equal "handler 1", handler1[1].call(1)
      assert_equal "queue_2", handler2[0][:queue]
      assert_equal "handler 2", handler2[1].call(1)
    end
  end
end
