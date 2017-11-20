require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class SubscriberTest < Minitest::Test
    def setup
      client = Client.new
      @sub = client.send(:subscriber)
    end

    test "initially there should be no amqp connections" do
      assert_equal({}, @sub.instance_variable_get("@connections"))
    end

    test "initially there should be no channels" do
      assert_equal({}, @sub.instance_variable_get("@channels"))
    end

    test "channel should return the channel associated with the current server, if there is one" do
      channel = mock("donald")
      @sub.instance_variable_set("@channels", {"donald:1" => channel})
      assert_nil @sub.send(:channel, "goofy:123")
      assert_equal channel, @sub.send(:channel, "donald:1")
    end

    test "stop! should close all amqp channels and connections and then stop the event loop if the reactor is running" do
      connection1 = mock('conection1')
      connection1.expects(:close).yields
      connection2 = mock('connection2')
      connection2.expects(:close).yields
      channel1 = mock('channel1')
      channel1.expects(:close)
      channel2 = mock('channel2')
      channel2.expects(:close)
      @sub.instance_variable_set "@connections", [["server1", connection1], ["server2", connection2]]
      @sub.instance_variable_set "@channels", {"server1" =>  channel1, "server2" => channel2}
      EM.expects(:reactor_running?).returns(true)
      EM.expects(:stop_event_loop)
      EM.expects(:add_timer).with(0).yields
      @sub.send(:stop!)
    end

    test "stop! should close all connections if the reactor is not running" do
      connection1 = mock('conection1')
      connection1.expects(:close).yields
      connection2 = mock('connection2')
      connection2.expects(:close).yields
      @sub.instance_variable_set "@connections", [["server1", connection1], ["server2", connection2]]
      EM.expects(:reactor_running?).returns(false)
      @sub.send(:stop!)
    end
  end

  class SubscriberPauseAndResumeTest < Minitest::Test
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
      @sub.servers << "localhost:7777"
      @server1, @server2 = @sub.servers
      @client.register_message(:a)
      @client.register_queue(:a)
      @client.register_handler(%W(a)){}
    end

    test "should pause on all servers when a handler has been registered" do
      @sub.expects(:pause).with("a").times(2)
      @sub.stubs(:has_subscription?).returns(true)
      @sub.pause_listening(%w(a))
    end

    test "should resume on all servers when a handler has been registered" do
      @sub.expects(:resume).with("a").times(2)
      @sub.stubs(:has_subscription?).returns(true)
      @sub.resume_listening(%w(a))
    end

    test "should pause on no servers when no handler has been registered" do
      @sub.expects(:pause).never
      @sub.stubs(:has_subscription?).returns(false)
      @sub.pause_listening(%w(a))
    end

    test "should resume on no servers when no handler has been registered" do
      @sub.expects(:resume).never
      @sub.stubs(:has_subscription?).returns(false)
      @sub.resume_listening(%w(a))
    end

    test "pausing a single queue should call amqp unsubscribe" do
      q = mock("queue a")
      q.expects(:subscribed?).returns(true)
      q.expects(:unsubscribe)
      @sub.stubs(:queues).returns({"a" =>q})
      @sub.__send__(:pause, "a")
    end

    test "pausing a single queue which is already paused should not call amqp unsubscribe" do
      q = mock("queue a")
      q.expects(:subscribed?).returns(false)
      q.expects(:unsubscribe).never
      @sub.stubs(:queues).returns({"a" =>q})
      @sub.__send__(:pause, "a")
    end

    test "resuming a single queue should call amqp subscribe" do
      q = mock("queue a")
      q.expects(:subscribed?).returns(false)
      q.expects(:subscribe)
      @sub.stubs(:queues).returns({"a" =>q})
      @sub.__send__(:resume, "a")
    end

    test "resuming a single queue which is already subscribed should not call amqp subscribe" do
      q = mock("queue a")
      q.expects(:subscribed?).returns(true)
      q.expects(:subscribe).never
      @sub.stubs(:queues).returns({"a" =>q})
      @sub.__send__(:resume, "a")
    end

  end

  class AdditionalSubscriptionServersTest < Minitest::Test
    def setup
      @config = Configuration.new
      @config.servers = "fetz:4321"
      @config.additional_subscription_servers = "braun:1234"
      @client = Client.new(@config)
      @sub = @client.send(:subscriber)
    end

    test "subscribers server list should contain addtional subcription hosts" do
      assert_equal ["fetz:4321", "braun:1234"], @sub.servers
    end
  end

  class SubscriberQueueManagementTest < Minitest::Test
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @sub.send(:queues))
      assert !@sub.send(:queues)["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @client.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange", "key" => "haha.#", "arguments" => {"schmu" => 5})
      @sub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("MQ")
      m.expects(:queue).with("some_queue", :durable => true, :passive => false, :auto_delete => false, :exclusive => false, :arguments => {"schmu" => 5}).returns(q)
      @sub.expects(:channel).returns(m).twice

      @sub.send(:queue, "some_queue")
      assert_equal q, @sub.send(:queues)["some_queue"]
    end

    test "binding queues should bind all queues" do
      @client.register_queue(:x)
      @client.register_queue(:y)
      @client.register_handler(%w(x y)){}
      @sub.expects(:queue).with("x")
      @sub.expects(:queue).with("y")
      @sub.send(:bind_queues, %W(x y))
    end

    test "subscribing to queues should subscribe on all queues" do
      @client.register_queue(:x)
      @client.register_queue(:y)
      @client.register_handler(%w(x y)){}
      @sub.expects(:subscribe).with("x")
      @sub.expects(:subscribe).with("y")
      @sub.send(:subscribe_queues, %W(x y))
    end

    test "should not try to bind a queue for an exchange which has no queue" do
      @client.register_message(:without_queue)
      assert_equal [], @sub.send(:queues_for_exchanges, ["without_queue"])
    end

    test "should not subscribe on a queue for which there is no handler" do
      @client.register_queue(:x)
      @client.register_queue(:y)
      @client.register_handler(%w(y)){}
      @sub.expects(:subscribe).with("y")
      @sub.send(:subscribe_queues, %W(x y))
    end

  end

  class SubscriberExchangeManagementTest < Minitest::Test
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
      @sub.expects(:channel).returns(m)
      ex = @sub.send(:exchange, "some_exchange")
      assert @sub.send(:exchanges).include?("some_exchange")
      ex2 = @sub.send(:exchange, "some_exchange")
      assert_equal ex2, ex
    end

    test "should create exchanges for all exchanges passed to create_exchanges for the current server" do
      @client.register_queue(:donald, :exchange => 'duck')
      @client.register_queue(:mickey)
      @client.register_queue(:mouse, :exchange => 'mickey')

      @sub.expects(:create_exchange!).with("duck", anything)
      @sub.expects(:create_exchange!).with("mickey", anything)
      @sub.send(:create_exchanges, %w(duck mickey))
    end
  end

  class DeadLetteringCallBackExecutionTest < Minitest::Test
    def setup
      @client = Client.new
      @client.config.dead_lettering_enabled = true
      @queue = "somequeue"
      @client.register_queue(@queue)
      @sub = @client.send(:subscriber)
      mq = mock("MQ")
      mq.expects(:closing?).returns(false)
      @sub.expects(:channel).with(@sub.server).returns(mq)
      @exception = Exception.new "murks"
      @handler = Handler.create(lambda{|*args| raise @exception})
      # handler method 'processing_completed' should be called under all circumstances
      @handler.expects(:processing_completed).once
      @callback = @sub.send(:create_subscription_callback, "my myessage", @queue, @handler, :exceptions => 1)
    end

    def teardown
      @client.config.dead_lettering_enabled = false
    end

    test "should call reject on the message header when processing the handler returns true on reject? if dead_lettering has been enabled" do
      header = header_with_params({})
      result = mock("result")
      result.expects(:reject?).returns(true)
      Message.any_instance.expects(:process).returns(result)
      @sub.expects(:sleep).never
      header.expects(:reject).with(:requeue => false)
      @callback.call(header, 'foo')
    end

  end

  class CallBackExecutionTest < Minitest::Test
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
      @handler.expects(:processing_completed).once
      header = header_with_params({})
      Message.any_instance.expects(:process).raises(Exception.new("don't worry"))
      channel = mock("MQ")
      channel.expects(:closing?).returns(false)
      @sub.expects(:channel).with(@sub.server).returns(channel)
      assert_nothing_raised { @callback.call(header, 'foo') }
    end

    test "callback should not process messages if the underlying channel has already been closed" do
      @handler.expects(:processing_completed).never
      header = header_with_params({})
      Message.any_instance.expects(:process).never
      channel = mock("channel")
      channel.expects(:closing?).returns(true)
      @sub.expects(:channel).with(@sub.server).returns(channel)
      assert_nothing_raised { @callback.call(header, 'foo') }
    end

    test "should call reject on the message header when processing the handler returns true on reject?" do
      @handler.expects(:processing_completed).once
      header = header_with_params({})
      result = mock("result")
      result.expects(:reject?).returns(true)
      Message.any_instance.expects(:process).returns(result)
      @sub.expects(:sleep).with(1)
      mq = mock("MQ")
      mq.expects(:closing?).returns(false)
      @sub.expects(:channel).with(@sub.server).returns(mq)
      header.expects(:reject).with(:requeue => true)
      @callback.call(header, 'foo')
    end

    test "should sent a reply with status OK if the message reply_to header is set and processing the handler succeeds" do
      @handler.expects(:processing_completed).once
      header = header_with_params(:reply_to => "tmp-queue")
      result = RC::OK
      Message.any_instance.expects(:process).returns(result)
      Message.any_instance.expects(:handler_result).returns("response-data")
      mq = mock("MQ")
      mq.expects(:closing?).returns(false)
      @sub.expects(:channel).with(@sub.server).returns(mq).twice
      exchange = mock("exchange")
      exchange.expects(:publish).with("response-data", :routing_key => "tmp-queue", :headers => {:status => "OK"}, :persistent => false)
      AMQP::Exchange.expects(:new).with(mq, :direct, "").returns(exchange)
      @callback.call(header, 'foo')
    end

    test "should sent a reply with status FAILED if the message reply_to header is set and processing the handler fails" do
      @handler.expects(:processing_completed).once
      header = header_with_params(:reply_to => "tmp-queue")
      result = RC::AttemptsLimitReached
      Message.any_instance.expects(:process).returns(result)
      Message.any_instance.expects(:handler_result).returns(nil)
      mq = mock("MQ")
      mq.expects(:closing?).returns(false)
      @sub.expects(:channel).with(@sub.server).returns(mq).twice
      exchange = mock("exchange")
      exchange.expects(:publish).with("", :routing_key => "tmp-queue", :headers => {:status => "FAILED"}, :persistent => false)
      AMQP::Exchange.expects(:new).with(mq, :direct, "").returns(exchange)
      @callback.call(header, 'foo')
    end

  end

  class SubscriptionTest < Minitest::Test
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
    end

    test "subscribe should subscribe with a subscription callback created from the registered block and remember the subscription" do
      @client.register_queue(:some_queue, :exchange => "some_exchange", :key => "some_key")
      server = @sub.server
      channel = mock("channel")
      channel.expects(:closing?).returns(false)
      @sub.expects(:channel).with(server).returns(channel)
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
      subscription_options = {:ack => true, :key => "#"}
      q.expects(:subscribe).with(subscription_options).yields(header, "foo")
      @sub.expects(:queues).returns({"some_queue" => q}).once
      @sub.send(:subscribe, "some_queue")
      assert block_called
      assert @sub.__send__(:has_subscription?, "some_queue")
      # q.expects(:subscribe).with(subscription_options).raises(MQ::Error)
      # assert_raises(Error) { @sub.send(:subscribe, "some_queue") }
    end

    test "subscribe should fail if no handler exists for given message" do
      assert_raises(Error){ @sub.send(:subscribe, "some_queue") }
    end

    test "listening on queues should use eventmachine, connect to each server, and yield" do
      @client.register_exchange(:an_exchange)
      @client.register_queue(:a_queue, :exchange => :an_exchange)
      @client.register_message(:a_message, :key => "foo", :exchange => :an_exchange)
      @sub.servers << "localhost:7777"

      @sub.expects(:connect_server).twice
      EM.expects(:run).yields
      # @sub.expects(:create_exchanges).with(["an_exchange"])
      # @sub.expects(:bind_queues).with(["a_queue"])
      # @sub.expects(:subscribe_queues).with(["a_queue"])
      yielded = false
      @sub.listen_queues(["a_queue"]) { yielded = true}
      assert yielded
    end
  end

  class HandlersTest < Minitest::Test
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

  class ConnectionTest < Minitest::Test
    def setup
      @client = Client.new
      @sub = @client.send(:subscriber)
      @sub.send(:set_current_server, "mickey:42")
      @settings = @sub.send(:connection_settings)
    end

    test "connection settings should use current host and port and specify connection failure callback" do
      assert_equal "mickey", @settings[:host]
      assert_equal 42, @settings[:port]
      assert @settings.has_key?(:on_tcp_connection_failure)
    end

    test "tcp connection failure should try to connect again after 10 seconds" do
      cb = @sub.send(:on_tcp_connection_failure)
      EM::Timer.expects(:new).with(10).yields
      @sub.expects(:connect_server).with(@settings)
      @sub.logger.expects(:warn).with("Beetle: connection failed: mickey:42")
      cb.call(@settings)
    end

    test "tcp connection loss handler tries to reconnect" do
      connection = mock("connection")
      connection.expects(:reconnect).with(false, 10)
      @sub.logger.expects(:warn).with("Beetle: lost connection: mickey:42. reconnecting.")
      @sub.send(:on_tcp_connection_loss, connection, {:host => "mickey", :port => 42})
    end

    test "event machine connection error" do
      connection = mock("connection")
      AMQP.expects(:connect).raises(EventMachine::ConnectionError)
      @settings[:on_tcp_connection_failure].expects(:call).with(@settings)
      @sub.send(:connect_server, @settings)
    end

    test "successfull connection to broker" do
      connection = mock("connection")
      connection.expects(:on_tcp_connection_loss)
      @sub.expects(:open_channel_and_subscribe).with(connection, @settings)
      AMQP.expects(:connect).with(@settings).yields(connection)
      @sub.send(:connect_server, @settings)
      assert_equal connection, @sub.instance_variable_get("@connections")["mickey:42"]
    end

    test "channel opening, exchange creation, queue bindings and subscription" do
      connection = mock("connection")
      channel = mock("channel")
      channel.expects(:prefetch).with(@client.config.prefetch_count)
      channel.expects(:auto_recovery=).with(true)
      AMQP::Channel.expects(:new).with(connection).yields(channel)
      @sub.expects(:create_exchanges)
      @sub.expects(:bind_queues)
      @sub.expects(:subscribe_queues)
      @sub.send(:open_channel_and_subscribe, connection, @settings)
      assert_equal channel, @sub.instance_variable_get("@channels")["mickey:42"]
    end

  end

end
