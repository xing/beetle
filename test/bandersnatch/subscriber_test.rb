require File.expand_path(File.dirname(__FILE__) + '/test_helper')


module Bandersnatch
  class SubscriberTest < Test::Unit::TestCase
    def setup
      @sub = Subscriber.new
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
      @sub = Subscriber.new
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
      @sub = Subscriber.new
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
end