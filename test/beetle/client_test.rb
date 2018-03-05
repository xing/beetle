require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class ClientDefaultsTest < Minitest::Test
    def setup
      @client = Client.new
    end

    test "should have a default server" do
      assert_equal ["#{ENV['RABBITMQ_HOST'] || 'localhost'}:5672"], @client.servers
    end

    test "should have no additional subscription servers" do
      assert_equal [], @client.additional_subscription_servers
    end

    test "should have no exchanges" do
      assert @client.exchanges.empty?
    end

    test "should have no queues" do
      assert @client.queues.empty?
    end

    test "should have no messages" do
      assert @client.messages.empty?
    end

    test "should have no bindings" do
      assert @client.bindings.empty?
    end
  end

  class RegistrationTest < Minitest::Test
    def setup
      @client = Client.new
    end

    test "registering an exchange should store it in the configuration with symbolized option keys and force a topic queue and durability" do
      opts = {"durable" => false, "type" => "fanout"}
      @client.register_exchange("some_exchange", opts)
      assert_equal({:durable => true, :type => :topic, :queues => []}, @client.exchanges["some_exchange"])
    end

    test "should convert exchange name to a string when registering an exchange" do
      @client.register_exchange(:some_exchange)
      assert(@client.exchanges.include?("some_exchange"))
    end

    test "registering an exchange should raise a configuration error if it is already configured" do
      @client.register_exchange("some_exchange")
      assert_raises(ConfigurationError){ @client.register_exchange("some_exchange") }
    end

    test "registering an exchange should initialize the list of queues bound to it" do
      @client.register_exchange("some_exchange")
      assert_equal [], @client.exchanges["some_exchange"][:queues]
      assert_raises(ConfigurationError){ @client.register_exchange("some_exchange") }
    end

    test "registering a queue should automatically register the corresponding exchange if it doesn't exist yet" do
      @client.register_queue("some_queue", "durable" => false, "exchange" => "some_exchange")
      assert @client.exchanges.include?("some_exchange")
    end

    test "registering a queue should store key and exchange in the bindings list" do
      @client.register_queue(:some_queue, :key => "some_key", :exchange => "some_exchange")
      assert_equal([{:key => "some_key", :exchange => "some_exchange"}], @client.bindings["some_queue"])
    end

    test "registering an additional binding for a queue should store key and exchange in the bindings list" do
      @client.register_queue(:some_queue, :key => "some_key", :exchange => "some_exchange")
      @client.register_binding(:some_queue, :key => "other_key", :exchange => "other_exchange")
      bindings = @client.bindings["some_queue"]
      expected_bindings = [{:key => "some_key", :exchange => "some_exchange"}, {:key => "other_key", :exchange => "other_exchange"}]
      assert_equal expected_bindings, bindings
    end

    test "registering a queue should store it in the configuration with symbolized option keys and force durable=true and passive=false and set the amqp queue name" do
      @client.register_queue("some_queue", "durable" => false, "exchange" => "some_exchange")
      assert_equal({:durable => true, :passive => false, :auto_delete => false, :exclusive => false, :amqp_name => "some_queue"}, @client.queues["some_queue"])
    end

    test "registering a queue should add the queue to the list of queues of the queue's exchange" do
      @client.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange")
      assert_equal ["some_queue"], @client.exchanges["some_exchange"][:queues]
    end

    test "registering two queues should add both queues to the list of queues of the queue's exchange" do
      @client.register_queue("queue1", :exchange => "some_exchange")
      @client.register_queue("queue2", :exchange => "some_exchange")
      assert_equal ["queue1","queue2"], @client.exchanges["some_exchange"][:queues]
    end

    test "registering a queue should raise a configuration error if it is already configured" do
      @client.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange")
      assert_raises(ConfigurationError){ @client.register_queue("some_queue") }
    end

    test "should convert queue name to a string when registering a queue" do
      @client.register_queue(:some_queue)
      assert(@client.queues.include?("some_queue"))
    end

    test "should convert exchange name to a string when registering a queue" do
      @client.register_queue(:some_queue, :exchange => :murks)
      assert_equal("murks", @client.bindings["some_queue"].first[:exchange])
    end

    test "registering a message should store it in the configuration with symbolized option keys" do
      opts = {"persistent" => true, "queue" => "some_queue", "exchange" => "some_exchange"}
      @client.register_queue("some_queue", "exchange" => "some_exchange")
      @client.register_message("some_message", opts)
      assert_equal({:persistent => true, :queue => "some_queue", :exchange => "some_exchange", :key => "some_message"}, @client.messages["some_message"])
    end

    test "registering a message should raise a configuration error if it is already configured" do
      opts = {"persistent" => true, "queue" => "some_queue"}
      @client.register_queue("some_queue", "exchange" => "some_exchange")
      @client.register_message("some_message", opts)
      assert_raises(ConfigurationError){ @client.register_message("some_message", opts) }
    end

    test "registering a message should register a corresponding exchange if it hasn't been registered yet" do
      opts = { "exchange" => "some_exchange" }
      @client.register_message("some_message", opts)
      assert_equal({:durable => true, :type => :topic, :queues => []}, @client.exchanges["some_exchange"])
    end

    test "registering a message should not fail if the exchange has already been registered" do
      opts = { "exchange" => "some_exchange" }
      @client.register_exchange("some_exchange")
      @client.register_message("some_message", opts)
      assert_equal({:durable => true, :type => :topic, :queues => []}, @client.exchanges["some_exchange"])
    end

    test "should convert message name to a string when registering a message" do
      @client.register_message(:some_message)
      assert(@client.messages.include?("some_message"))
    end

    test "should convert exchange name to a string when registering a message" do
      @client.register_message(:some_message, :exchange => :murks)
      assert_equal("murks", @client.messages["some_message"][:exchange])
    end

    test "configure should yield a configurator configured with the client and the given options" do
      options = {:exchange => :foobar}
      Client::Configurator.expects(:new).with(@client, options).returns(42)
      @client.configure(options) {|config| assert_equal 42, config}
    end

    test "configure should eval a passed block without arguments in the context of the configurator" do
      options = {:exchange => :foobar}
      m = "mock"
      m.expects(:foo).returns(42)
      Client::Configurator.expects(:new).with(@client, options).returns(m)
      value = nil
      @client.configure(options) { value = foo }
      assert_equal 42, value
    end

    test "a configurator should forward all known registration methods to the client" do
      options = {:foo => :bar}
      config = Client::Configurator.new(@client, options)
      @client.expects(:register_exchange).with(:a, options)
      config.exchange(:a)

      @client.expects(:register_queue).with(:q, options.merge(:exchange => :foo))
      config.queue(:q, :exchange => :foo)

      @client.expects(:register_binding).with(:b, options.merge(:key => :baz))
      config.binding(:b, :key => :baz)

      @client.expects(:register_message).with(:m, options.merge(:exchange => :foo))
      config.message(:m, :exchange => :foo)

      @client.expects(:register_handler).with(:h, options.merge(:queue => :q))
      config.handler(:h, :queue => :q)

      assert_raises(NoMethodError){ config.moo }
    end

    test "a configurator should forward all known registration methods to the client (no arguments block syntax)" do
      options = {:foo => :bar}
      config = Client::Configurator.new(@client, options)
      @client.expects(:register_exchange).with(:a, options)
      @client.expects(:register_queue).with(:q, options.merge(:exchange => :foo))
      @client.expects(:register_binding).with(:b, options.merge(:key => :baz))
      @client.expects(:register_message).with(:m, options.merge(:exchange => :foo))
      @client.expects(:register_handler).with(:h, options.merge(:queue => :q))
      @client.configure(options) do
        exchange(:a)
        queue(:q, :exchange => :foo)
        binding(:b, :key => :baz)
        message(:m, :exchange => :foo)
        handler(:h, :queue => :q)
      end

      assert_raises(NoMethodError){ @client.configure{moo(3)} }
    end

  end

  class ClientTest < Minitest::Test
    test "#reset should stop subscriber and publisher" do
      client = Client.new
      client.send(:publisher).expects(:stop)
      client.send(:subscriber).expects(:stop!)
      client.reset
    end

    test "#reset should reload the configuration" do
      client = Client.new
      client.config.expects(:reload)
      client.reset
    end

    test "#reset should not propagate exceptions" do
      client = Client.new
      client.expects(:config).raises(ArgumentError)
      client.reset
    end

    test "instantiating a client should not instantiate the subscriber/publisher" do
      Publisher.expects(:new).never
      Subscriber.expects(:new).never
      Client.new
    end

    test "should instantiate a subscriber when used for subscribing" do
      Subscriber.expects(:new).returns(stub_everything("subscriber"))
      client = Client.new
      client.register_queue("superman")
      client.register_message("superman")
      client.register_handler("superman", {}, &lambda{})
    end

    test "should instantiate a subscriber when used for publishing" do
      client = Client.new
      client.register_message("foobar")
      Publisher.expects(:new).returns(stub_everything("subscriber"))
      client.publish("foobar", "payload")
    end

    test "should delegate publishing to the publisher instance" do
      client = Client.new
      client.register_message("deadletter")
      args = ["deadletter", "x", {:a => 1}]
      client.send(:publisher).expects(:publish).with(*args).returns(1)
      assert_equal 1, client.publish(*args)
    end

    test "should convert message name to a string when publishing" do
      client = Client.new
      client.register_message("deadletter")
      args = [:deadletter, "x", {:a => 1}]
      client.send(:publisher).expects(:publish).with("deadletter", "x", :a => 1).returns(1)
      assert_equal 1, client.publish(*args)
    end

    test "should convert message name to a string on rpc" do
      client = Client.new
      client.register_message("deadletter")
      args = [:deadletter, "x", {:a => 1}]
      client.send(:publisher).expects(:rpc).with("deadletter", "x", :a => 1).returns(1)
      assert_equal 1, client.rpc(*args)
    end

    test "trying to publish an unknown message should raise an exception" do
      assert_raises(UnknownMessage) { Client.new.publish("foobar") }
    end

    test "trying to RPC an unknown message should raise an exception" do
      assert_raises(UnknownMessage) { Client.new.rpc("foobar") }
    end

    test "should delegate stop_publishing to the publisher instance" do
      client = Client.new
      client.send(:publisher).expects(:stop)
      client.stop_publishing
    end

    test "should delegate queue purging to the publisher instance" do
      client = Client.new
      client.register_queue(:queue)
      client.send(:publisher).expects(:purge).with(["queue"]).returns("ha!")
      assert_equal "ha!", client.purge("queue")
    end

    test "purging a queue should convert the queue name to a string" do
      client = Client.new
      client.register_queue(:queue)
      client.send(:publisher).expects(:purge).with(["queue"]).returns("ha!")
      assert_equal "ha!", client.purge(:queue)
    end

    test "trying to purge an unknown queue should raise an exception" do
      assert_raises(UnknownQueue) { Client.new.purge(:mumu) }
    end

    test "should be possible to purge multiple queues with a single call" do
      client = Client.new
      client.register_queue(:queue1)
      client.register_queue(:queue2)
      client.send(:publisher).expects(:purge).with(["queue1","queue2"]).returns("ha!")
      assert_equal "ha!", client.purge(:queue1, :queue2)
    end

    test "should delegate rpc calls to the publisher instance" do
      client = Client.new
      client.register_message("deadletter")
      args = ["deadletter", "x", {:a => 1}]
      client.send(:publisher).expects(:rpc).with(*args).returns("ha!")
      assert_equal "ha!", client.rpc(*args)
    end

    test "should delegate listening to the subscriber instance" do
      client = Client.new
      client.register_queue("b_queue")
      client.register_queue("a_queue")
      client.send(:subscriber).expects(:listen_queues).with {|value| value.include?("a_queue") && value.include?("b_queue")}.yields
      client.listen
    end

    test "trying to listen to a message is no longer supported and should raise an exception" do
      assert_raises(Error) { Client.new.listen([:a])}
    end

    test "should delegate listening to queues to the subscriber instance" do
      client = Client.new
      client.register_queue(:test)
      client.send(:subscriber).expects(:listen_queues).with(['test']).yields
      client.listen_queues([:test])
    end

    test "trying to listen to an unknown queue should raise an exception" do
      client = Client.new
      assert_raises(UnknownQueue) { Client.new.listen_queues([:foobar])}
    end

    test "trying to pause listening on an unknown queue should raise an exception" do
      client = Client.new
      assert_raises(UnknownQueue) { Client.new.pause_listening(:foobar)}
    end

    test "trying to resume listening on an unknown queue should raise an exception" do
      client = Client.new
      assert_raises(UnknownQueue) { Client.new.pause_listening(:foobar)}
    end

    test "should delegate stop_listening to the subscriber instance" do
      client = Client.new
      client.send(:subscriber).expects(:stop!)
      client.stop_listening
    end

    test "should delegate pause_listening to the subscriber instance" do
      client = Client.new
      client.register_queue(:test)
      client.send(:subscriber).expects(:pause_listening).with(%w(test))
      client.pause_listening(:test)
    end

    test "should delegate resume_listening to the subscriber instance" do
      client = Client.new
      client.register_queue(:test)
      client.send(:subscriber).expects(:resume_listening).with(%w(test))
      client.resume_listening(:test)
    end

    test "should delegate handler registration to the subscriber instance" do
      client = Client.new
      client.register_queue("huhu")
      client.send(:subscriber).expects(:register_handler)
      client.register_handler("huhu")
    end

    test "should convert queue names to strings when registering a handler" do
      client = Client.new
      client.register_queue(:haha)
      client.register_queue(:huhu)
      client.send(:subscriber).expects(:register_handler).with(["huhu", "haha"], {}, nil)
      client.register_handler([:huhu, :haha])
    end

    test "should use the configured logger" do
      client = Client.new
      Beetle.config.expects(:logger)
      client.logger
    end

    test "load should expand the glob argument and evaluate each file in the client instance" do
      client = Client.new
      File.expects(:read).returns("1+1")
      client.expects(:eval).with("1+1",anything,anything)
      client.load("#{File.dirname(__FILE__)}/../../**/client_test.rb")
    end

    test "tracing should modify the amqp options for each queue and register a handler for each queue" do
      client = Client.new
      client.register_queue("test")
      sub = client.send(:subscriber)
      sub.expects(:register_handler).with(client.queues.keys, {}, nil).yields(message_stub_for_tracing)
      sub.expects(:listen_queues)
      client.stubs(:puts)
      client.trace
      test_queue_opts = client.queues["test"]
      expected_name = client.send :queue_name_for_tracing, "test"
      assert_equal expected_name, test_queue_opts[:amqp_name]
      assert test_queue_opts[:auto_delete]
      assert !test_queue_opts[:durable]
    end

    test "limiting tracing to some queues" do
      client = Client.new
      client.register_queue("test")
      client.register_queue("irrelevant")
      sub = client.send(:subscriber)
      sub.expects(:register_handler).with(["test"], {}, nil).yields(message_stub_for_tracing)
      sub.expects(:listen_queues).with(["test"])
      client.stubs(:puts)
      client.trace(["test"])
    end

    def message_stub_for_tracing
      header_stub = stub_everything("header")
      header_stub.stubs(:method).returns(stub_everything("method"))
      header_stub.stubs(:attributes).returns(stub_everything("attributes"))
      msg_stub = stub_everything("message")
      msg_stub.stubs(:header).returns(header_stub)
      msg_stub
    end
  end
end
