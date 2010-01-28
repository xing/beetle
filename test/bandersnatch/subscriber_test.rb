require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Bandersnatch
  class SubscriberTest < Test::Unit::TestCase
    def setup
      client = mock("client")
      @sub = Subscriber.new(client)
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
      AMQP.expects(:connect).with(:host => @sub.current_host, :port => @sub.current_port).returns(m)
      # TODO: smarter way to test? what triggers the amqp_connection private method call?
      assert_equal m, @sub.send(:new_amqp_connection)
    end

    test "mq instances should be created for the current server if accessed" do
      @sub.expects(:amqp_connection).returns(11)
      MQ.expects(:new).with(11).returns(42)
      assert_equal 42, @sub.mq
      mqs = @sub.instance_variable_get("@mqs")
      assert_equal 42, mqs[@sub.server]
    end
  end

  class SubscriberQueueManagementTest < Test::Unit::TestCase
    def setup
      client = mock("client")
      @sub = Subscriber.new(client)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @sub.queues)
      assert !@sub.queues["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @sub.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange", "key" => "haha.#")
      @sub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("MQ")
      m.expects(:queue).with("some_queue", :durable => true).returns(q)
      @sub.expects(:mq).returns(m)

      @sub.bind_queue("some_queue")
      assert_equal q, @sub.queues["some_queue"]
    end
  end

  class SubscriberExchangeManagementTest < Test::Unit::TestCase
    def setup
      client = mock("client")
      @sub = Subscriber.new(client)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @sub.exchanges_for_current_server)
      assert !@sub.exchange_exists?("some_message")
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      @sub.register_exchange("some_exchange", "type" => "topic", "durable" => true)
      m = mock("AMQP")
      m.expects(:topic).with("some_exchange", :durable => true).returns(42)
      @sub.expects(:mq).returns(m)
      ex = @sub.exchange("some_exchange")
      assert @sub.exchange_exists?("some_exchange")
      ex2 = @sub.exchange("some_exchange")
      assert_equal ex2, ex
    end

    test "should create exchanges for all registered messages and servers" do
      @sub.servers = %w(x y)
      messages = %w(a b)
      exchange_creation = sequence("exchange creation")
      @sub.messages = []
      @sub.expects(:set_current_server).with('x').in_sequence(exchange_creation)
      @sub.expects(:create_exchange).with("a").in_sequence(exchange_creation)
      @sub.expects(:create_exchange).with("b").in_sequence(exchange_creation)
      @sub.expects(:set_current_server).with('y').in_sequence(exchange_creation)
      @sub.expects(:create_exchange).with("a").in_sequence(exchange_creation)
      @sub.expects(:create_exchange).with("b").in_sequence(exchange_creation)
      @sub.create_exchanges(messages)
    end
  end

  class DeDuplificationTest < Test::Unit::TestCase
    def setup
      client = mock("client")
      @sub = Subscriber.new(client)
      @handler = mock("handler")
      @queue = 'somequeue'
      @callback = @sub.send(:create_subscription_callback, 'servername', @queue, @handler)
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

  class SubscriptionTest < Test::Unit::TestCase
    def setup
      @client = mock("client")
      @sub = Subscriber.new(@client)
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
        assert_nil m.uuid
      end
      @client.stubs(:handlers).returns({"some_message" => [[opts.symbolize_keys, proc]]})
      q = mock("QUEUE")
      q.expects(:subscribe).with({:ack => true, :key => "some_key.#"}).yields(header, Message.encode("data"))
      @sub.expects(:queues).returns({"some_message" => q})
      @sub.send(:subscribe_message, "some_message")
      assert block_called
    end

    test "subscribe should fail if no handler exists for given message" do
      @client.stubs(:handlers).returns({})
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
end