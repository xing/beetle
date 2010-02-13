require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class PublisherTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @pub = Publisher.new(client)
    end

    test "acccessing a bunny for a server which doesn't have one should create it and associate it with the server" do
      @pub.expects(:new_bunny).returns(42)
      assert_equal 42, @pub.send(:bunny)
      bunnies = @pub.instance_variable_get("@bunnies")
      assert_equal(42, bunnies[@pub.server])
    end

    test "new bunnies should be created using current host and port and they should be started" do
      m = mock("dummy")
      Bunny.expects(:new).with(:host => @pub.send(:current_host), :port => @pub.send(:current_port), :logging => false).returns(m)
      m.expects(:start)
      assert_equal m, @pub.send(:new_bunny)
    end

    test "initially there should be no bunnies" do
      assert_equal({}, @pub.instance_variable_get("@bunnies"))
    end

    test "initially there should be no dead servers" do
      assert_equal({}, @pub.instance_variable_get("@dead_servers"))
    end

    test "stop! should shut down bunny and clean internal data structures" do
      b = mock("bunny")
      b.expects(:stop).raises(Exception.new)
      @pub.expects(:bunny).returns(b)
      @pub.send(:stop!)
      assert_equal({}, @pub.send(:exchanges_for_current_server))
      assert_equal({}, @pub.send(:queues))
      assert_nil @pub.instance_variable_get(:@bunnies)[@pub.server]
    end

  end

  class PublisherPublishingTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @pub = Publisher.new(@client)
      @pub.stubs(:bind_queues_for_exchange)
      @client.register_exchange("mama-exchange")
      @client.register_queue("mama", :exchange => "mama-exchange")
      @client.register_message("mama", :ttl => 1.hour)
      @opts = { :ttl => 1.hour }
      @data = 'XXX'
    end

    test "failover publishing should try to recycle dead servers before trying to publish the message" do
      publishing = sequence('publishing')
      @pub.expects(:recycle_dead_servers).in_sequence(publishing)
      @pub.expects(:publish_with_failover).with("mama-exchange", "mama", @data, @opts).in_sequence(publishing)
      @pub.publish("mama", @data)
    end

    test "redundant publishing should try to recycle dead servers before trying to publish the message" do
      publishing = sequence('publishing')
      @pub.expects(:recycle_dead_servers).in_sequence(publishing)
      @pub.expects(:publish_with_redundancy).with("mama-exchange", "mama", @data, @opts.merge(:redundant => true)).in_sequence(publishing)
      @pub.publish("mama", @data, :redundant => true)
    end

    test "publishing should fail over to the next server" do
      failover = sequence('failover')
      @pub.expects(:select_next_server).in_sequence(failover)
      e = mock("exchange")
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(failover)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(failover)
      @pub.expects(:stop!).in_sequence(failover)
      @pub.expects(:mark_server_dead).in_sequence(failover)
      @pub.publish_with_failover("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should send the message to two servers" do
      redundant = sequence("redundant")
      @pub.servers = ["someserver", "someotherserver"]
      @pub.server = "someserver"

      e = mock("exchange")
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 2, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should return 1 if the message was published to one server only" do
      redundant = sequence("redundant")
      @pub.servers = ["someserver", "someotherserver"]
      @pub.server = "someserver"

      e = mock("exchange")
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 1, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should return 0 if the message was published to no server" do
      redundant = sequence("redundant")
      @pub.servers = ["someserver", "someotherserver"]
      @pub.server = "someserver"

      e = mock("exchange")
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(redundant)

      assert_equal 0, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should fallback to failover publishing if less than one server is available" do
      @pub.server = ["a server"]
      @pub.expects(:publish_with_failover).with("mama-exchange", "mama", @data, @opts).returns(1)
      assert_equal 1, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should publish to two of three servers if one server is dead" do
      @pub.servers = %w(server1 server2 server3)
      @pub.server = "server1"
      redundant = sequence("redundant")

      e = mock("exchange")

      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(redundant)
      @pub.expects(:stop!).in_sequence(redundant)

      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 2, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "publishing should use the message ttl passed in the options hash to encode the message body" do
      opts = {:ttl => 1.day}
      Message.expects(:encode).with(@data, :ttl => 1.day)
      @pub.expects(:select_next_server)
      e = mock("exchange")
      @pub.expects(:exchange).returns(e)
      e.expects(:publish)
      assert_equal 1, @pub.publish_with_failover("mama-exchange", "mama", @data, opts)
    end

    test "publishing with redundancy should use the message ttl passed in the options hash to encode the message body" do
      @data = "XXX"
      opts = {:ttl => 1.day}
      Message.expects(:encode).with(@data, :ttl => 1.day)
      @pub.expects(:select_next_server)
      e = mock("exchange")
      @pub.expects(:exchange).returns(e)
      e.expects(:publish)
      assert_equal 1, @pub.publish_with_redundancy("mama-exchange", "mama", @data, opts)
    end

    test "publishing should use the message ttl from the message configuration if no ttl is passed in via the options hash" do
      @pub.expects(:publish_with_failover).with("mama-exchange", "mama", @data, @opts).returns(1)
      assert_equal 1, @pub.publish("mama", @data)
    end
  end

  class PublisherQueueManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @pub = Publisher.new(@client)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @pub.send(:queues))
      assert !@pub.send(:queues)["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @client.register_exchange("some_exchange")
      @client.register_queue("some_queue", :durable => true, :exchange => "some_exchange", :key => "haha.#")
      @pub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("Bunny")
      m.expects(:queue).with("some_queue", :durable => true, :passive => false).returns(q)
      @pub.expects(:bunny).returns(m)

      @pub.send(:bind_queue, "some_queue")
      assert_equal q, @pub.send(:queues)["some_queue"]
    end

    test "should bind the defined queues for the used exchanges when publishing" do
      @client.register_exchange("test_exchange")
      @client.register_queue('test_queue_1', 'exchange' => 'test_exchange')
      @client.register_queue('test_queue_2', 'exchange' => 'test_exchange')
      @pub.expects(:bind_queue).with('test_queue_1')
      @pub.expects(:bind_queue).with('test_queue_2')
      @pub.send(:bind_queues_for_exchange, 'test_exchange')
    end

    test "should not rebind the defined queues for the used exchanges if they already have been bound" do
      @client.register_exchange("test_exchange")
      @client.register_queue('test_queue_1', 'exchange' => 'test_exchange')
      @client.register_queue('test_queue_2', 'exchange' => 'test_exchange')
      @pub.expects(:bind_queue!).twice
      @pub.send(:bind_queues_for_exchange, 'test_exchange')
      @pub.send(:bind_queues_for_exchange, 'test_exchange')
    end

    test "call the queue binding method when publishing" do
      data = "XXX"
      opts = {}
      @client.register_exchange("mama-exchange")
      @client.register_queue("mama", :exchange => "mama-exchange")
      @client.register_message("mama", :ttl => 1.hour)
      e = stub('exchange', 'publish')
      @pub.expects(:exchange).with('mama-exchange').returns(e)
      @pub.expects(:bind_queues_for_exchange).with('mama-exchange').returns(true)
      @pub.publish('mama', data)
    end
  end

  class PublisherExchangeManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @pub = Publisher.new(@client)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @pub.send(:exchanges_for_current_server))
      assert !@pub.send(:exchange_exists?, "some_message")
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      m = mock("Bunny")
      m.expects(:exchange).with("some_exchange", :type => :topic, :durable => true).returns(42)
      @client.register_exchange("some_exchange", :type => :topic, :durable => true)
      @pub.expects(:bunny).returns(m)
      ex  = @pub.send(:exchange, "some_exchange")
      assert @pub.send(:exchange_exists?, "some_exchange")
      ex2 = @pub.send(:exchange, "some_exchange")
      assert_equal ex2, ex
    end
  end

  class PublisherServerManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @pub = Publisher.new(@client)
    end

    test "marking the current server as dead should add it to the dead servers hash and remove it from the active servers list" do
      @pub.servers = ["localhost:1111", "localhost:2222"]
      @pub.send(:set_current_server, "localhost:2222")
      @pub.send(:mark_server_dead)
      assert_equal ["localhost:1111"], @pub.servers
      dead = @pub.instance_variable_get "@dead_servers"
      assert_equal ["localhost:2222"], dead.keys
      assert_kind_of Time, dead["localhost:2222"]
    end

    test "should create exchanges for all registered messages and servers" do
      @pub.servers = %w(x y)
      messages = %w(a b)
      @client.register_exchange('margot')
      @client.register_exchange('mickey')
      @client.register_queue('donald', 'exchange' => 'margot')
      @client.register_queue('mickey')
      @client.register_message('a', 'queue' => 'donald')
      @client.register_message('b', 'queue' => 'mickey')

      exchange_creation = sequence("exchange creation")
      @pub.expects(:set_current_server).with('x').in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("margot").in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("mickey").in_sequence(exchange_creation)
      @pub.expects(:set_current_server).with('y').in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("margot").in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("mickey").in_sequence(exchange_creation)
      @pub.send(:create_exchanges, messages)
    end

    test "recycle_dead_servers should move servers from the dead server hash to the servers list only if the have been markd dead for longer than 10 seconds" do
      @pub.servers = ["a:1", "b:2"]
      @pub.send(:set_current_server, "a:1")
      @pub.send(:mark_server_dead)
      assert_equal ["b:2"], @pub.servers
      dead = @pub.instance_variable_get("@dead_servers")
      dead["a:1"] = 9.seconds.ago
      @pub.send(:recycle_dead_servers)
      assert_equal ["a:1"], dead.keys
      dead["a:1"] = 11.seconds.ago
      @pub.send(:recycle_dead_servers)
      assert_equal ["b:2", "a:1"], @pub.servers
      assert_equal({}, dead)
    end

    test "select_next_server should cycle through the list of all servers" do
      @pub.servers = ["a:1", "b:2"]
      @pub.send(:set_current_server, "a:1")
      @pub.send(:select_next_server)
      assert_equal "b:2", @pub.server
      @pub.send(:select_next_server)
      assert_equal "a:1", @pub.server
    end

    test "select_next_server should return o if there are no servers to publish to" do
      @pub.servers = []
      logger = mock('logger')
      logger.expects(:error).returns(true)
      @pub.expects(:logger).returns(logger)
      @pub.expects(:message_name).returns('foo')
      assert_equal 0, @pub.send(:select_next_server)
    end
  end
end
