require File.expand_path(File.dirname(__FILE__) + '/test_helper')


module Bandersnatch
  class ConfigTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:pub)
    end

    test "mode should be set if valid" do
      assert_equal :pub, @bs.mode
      bs = Base.new(:sub)
      assert_equal :sub, bs.mode
    end

    test "initializing should fail for invalid mode" do
      assert_raises(Error) { Base.new(:murks) }
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

  class BandersnatchPublisherTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:pub)
    end

    test "acccessing a bunny for a server which doesn't have one should create it and associate it with the server" do
      @bs.expects(:new_bunny).returns(42)
      assert_equal 42, @bs.bunny
      bunnies = @bs.instance_variable_get("@bunnies")
      assert_equal(42, bunnies[@bs.server])
    end

    test "new bunnies should be created using current host and port and they should be started" do
      m = mock("dummy")
      Bunny.expects(:new).with(:host => @bs.current_host, :port => @bs.current_port, :logging => false).returns(m)
      m.expects(:start)
      assert_equal m, @bs.new_bunny
    end

  end

  class SubscriberTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:sub)
    end

    test "acccessing an amq_connection for a server which doesn't have one should create it and associate it with the server" do
      @bs.expects(:new_amqp_connection).returns(42)
      assert_equal 42, @bs.amqp_connection
      connections = @bs.instance_variable_get("@amqp_connections")
      assert_equal 42, connections[@bs.server]
    end

    test "new amqp connections should be created using current host and port" do
      m = mock("dummy")
      AMQP.expects(:connect).with(:host => @bs.current_host, :port => @bs.current_port).returns(m)
      assert_equal m, @bs.new_amqp_connection
    end

    test "mq instances should be created for the current server if accessed" do
      @bs.expects(:amqp_connection).returns(11)
      MQ.expects(:new).with(11).returns(42)
      assert_equal 42, @bs.mq
      mqs = @bs.instance_variable_get("@mqs")
      assert_equal 42, mqs[@bs.server]
    end
  end

  class BandersnatchHandlerRegistrationTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:sub)
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

  class SubscriberExchangeManagementTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:sub)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @bs.exchanges_for_current_server)
      assert !@bs.exchange_exists?("some_message")
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      @bs.register_exchange("some_exchange", "type" => "topic", "durable" => true)
      m = mock("AMQP")
      m.expects(:topic).with("some_exchange", :durable => true).returns(42)
      @bs.expects(:mq).returns(m)
      ex = @bs.exchange("some_exchange")
      assert @bs.exchange_exists?("some_exchange")
      ex2 = @bs.exchange("some_exchange")
      assert_equal ex2, ex
    end

    test "should create exchanges for all registered messages and servers" do
      @bs.servers = %w(x y)
      messages = %w(a b)
      exchange_creation = sequence("exchange creation")
      @bs.messages = []
      @bs.expects(:set_current_server).with('x').in_sequence(exchange_creation)
      @bs.expects(:create_exchange).with("a").in_sequence(exchange_creation)
      @bs.expects(:create_exchange).with("b").in_sequence(exchange_creation)
      @bs.expects(:set_current_server).with('y').in_sequence(exchange_creation)
      @bs.expects(:create_exchange).with("a").in_sequence(exchange_creation)
      @bs.expects(:create_exchange).with("b").in_sequence(exchange_creation)
      @bs.create_exchanges(messages)
    end
  end

  class PublisherExchangeManagementTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:pub)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @bs.exchanges_for_current_server)
      assert !@bs.exchange_exists?("some_message")
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      @bs.register_exchange("some_exchange", "type" => "topic", "durable" => true)
      m = mock("Bunny")
      m.expects(:exchange).with("some_exchange", :type => :topic, :durable => true).returns(42)
      @bs.expects(:bunny).returns(m)
      ex = @bs.exchange("some_exchange")
      assert @bs.exchange_exists?("some_exchange")
      ex2 = @bs.exchange("some_exchange")
      assert_equal ex2, ex
    end
  end

  class SubscriberQueueManagementTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:sub)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @bs.queues)
      assert !@bs.queues["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @bs.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange", "key" => "haha.#")
      @bs.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("MQ")
      m.expects(:queue).with("some_queue", :durable => true).returns(q)
      @bs.expects(:mq).returns(m)

      @bs.bind_queue("some_queue")
      assert_equal q, @bs.queues["some_queue"]
    end
  end

  class PublisherQueueManagementTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:pub)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @bs.queues)
      assert !@bs.queues["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @bs.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange", "key" => "haha.#")
      @bs.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("Bunny")
      m.expects(:queue).with("some_queue", :durable => true).returns(q)
      @bs.expects(:bunny).returns(m)

      @bs.bind_queue("some_queue")
      assert_equal q, @bs.queues["some_queue"]
    end
  end

  class SubscriptionTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:sub)
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
      @bs = Base.new(:sub)
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

  class PublisherPublishingTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:pub)
    end

    test "publishing should try to recycle dead servers before trying to publish the message" do
      publishing = sequence('publishing')
      data = "XXX"
      @bs.expects(:recycle_dead_servers).in_sequence(publishing)
      @bs.expects(:publish_with_failover).with("mama", "mama", data, {}).in_sequence(publishing)
      @bs.publish("mama", data)
    end

    test "publishing should fail over to the next server" do
      failover = sequence('failover')
      data = "XXX"
      opts = {}
      @bs.expects(:select_next_server).in_sequence(failover)
      e = mock("exchange")
      @bs.expects(:exchange).with("mama").returns(e).in_sequence(failover)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(failover)
      @bs.expects(:stop_bunny).in_sequence(failover)
      @bs.expects(:mark_server_dead).in_sequence(failover)
      @bs.expects(:error).in_sequence(failover)
      @bs.publish_with_failover("mama", "mama", data, opts)
    end

    test "redundant publishing should send the message to two servers" do
      data = "XXX"
      opts = {}
      redundant = sequence("redundant")
      @bs.servers = ["someserver", "someotherserver"]

      e = mock("exchange")
      @bs.expects(:select_next_server).in_sequence(redundant)
      @bs.expects(:exchange).with("mama").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)
      @bs.expects(:select_next_server).in_sequence(redundant)
      @bs.expects(:exchange).with("mama").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 2, @bs.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "redundant publishing should fallback to failover publishing if less than one server is available" do
      @bs.server = ["a server"]
      data = "XXX"
      opts = {}
      @bs.expects(:publish_with_failover).with("mama", "mama", data, opts).returns(1)
      assert_equal 1, @bs.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "redundant publishing should try switching servers until a server is available for publishing" do
      @bs.servers = %w(server1 server2 server3)
      data = "XXX"
      opts = {}
      redundant = sequence("redundant")

      e = mock("exchange")

      @bs.expects(:select_next_server).in_sequence(redundant)
      @bs.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      @bs.expects(:select_next_server).in_sequence(redundant)
      @bs.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(redundant)
      @bs.expects(:stop_bunny).in_sequence(redundant)
      @bs.expects(:mark_server_dead).in_sequence(redundant)

      @bs.expects(:select_next_server).in_sequence(redundant)
      @bs.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 2, @bs.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "publishing should use the message ttl passed in the options hash to encode the message body" do
      data = "XXX"
      opts = {:ttl => 1.day}
      Message.expects(:encode).with(data, :ttl => 1.day)
      @bs.expects(:select_next_server)
      e = mock("exchange")
      @bs.expects(:exchange).returns(e)
      e.expects(:publish)
      assert_equal 1, @bs.publish_with_failover("mama", "mama", data, opts)
    end

    test "publishing with redundancy should use the message ttl passed in the options hash to encode the message body" do
      data = "XXX"
      opts = {:ttl => 1.day}
      Message.expects(:encode).with(data, :ttl => 1.day)
      @bs.expects(:select_next_server)
      e = mock("exchange")
      @bs.expects(:exchange).returns(e)
      e.expects(:publish)
      assert_equal 1, @bs.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "publishing should use the message ttl from the message configuration if no ttl is passed in via the options hash" do
      data = "XXX"
      opts = {}
      @bs.messages["mama"] = {:ttl => 1.hour}
      @bs.expects(:publish_with_failover).with("mama", "mama", data, :ttl => 1.hour).returns(1)
      assert_equal 1, @bs.publish("mama", data)
    end

  end

  class DeDuplificationTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(:sub)
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