require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Bandersnatch
  class PublisherTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @pub = Publisher.new(client)
    end

    test "acccessing a bunny for a server which doesn't have one should create it and associate it with the server" do
      @pub.expects(:new_bunny).returns(42)
      assert_equal 42, @pub.bunny
      bunnies = @pub.instance_variable_get("@bunnies")
      assert_equal(42, bunnies[@pub.server])
    end

    test "new bunnies should be created using current host and port and they should be started" do
      m = mock("dummy")
      Bunny.expects(:new).with(:host => @pub.send(:current_host), :port => @pub.send(:current_port), :logging => false).returns(m)
      m.expects(:start)
      assert_equal m, @pub.new_bunny
    end

    test "initially there should be no bunnies" do
      assert_equal({}, @pub.instance_variable_get("@bunnies"))
    end

    test "initially there should be no dead servers" do
      assert_equal({}, @pub.instance_variable_get("@dead_servers"))
    end
  end

  class PublisherPublishingTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @pub = Publisher.new(client)
    end

    test "publishing should try to recycle dead servers before trying to publish the message" do
      publishing = sequence('publishing')
      data = "XXX"
      @pub.expects(:recycle_dead_servers).in_sequence(publishing)
      @pub.expects(:publish_with_failover).with("mama", "mama", data, {}).in_sequence(publishing)
      @pub.publish("mama", data)
    end

    test "publishing should fail over to the next server" do
      failover = sequence('failover')
      data = "XXX"
      opts = {}
      @pub.expects(:select_next_server).in_sequence(failover)
      e = mock("exchange")
      @pub.expects(:exchange).with("mama").returns(e).in_sequence(failover)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(failover)
      @pub.expects(:stop!).in_sequence(failover)
      @pub.expects(:mark_server_dead).in_sequence(failover)
      @pub.expects(:error).in_sequence(failover)
      @pub.publish_with_failover("mama", "mama", data, opts)
    end

    test "redundant publishing should send the message to two servers" do
      data = "XXX"
      opts = {}
      redundant = sequence("redundant")
      @pub.servers = ["someserver", "someotherserver"]

      e = mock("exchange")
      @pub.expects(:select_next_server).in_sequence(redundant)
      @pub.expects(:exchange).with("mama").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)
      @pub.expects(:select_next_server).in_sequence(redundant)
      @pub.expects(:exchange).with("mama").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 2, @pub.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "redundant publishing should fallback to failover publishing if less than one server is available" do
      @pub.server = ["a server"]
      data = "XXX"
      opts = {}
      @pub.expects(:publish_with_failover).with("mama", "mama", data, opts).returns(1)
      assert_equal 1, @pub.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "redundant publishing should try switching servers until a server is available for publishing" do
      @pub.servers = %w(server1 server2 server3)
      data = "XXX"
      opts = {}
      redundant = sequence("redundant")

      e = mock("exchange")

      @pub.expects(:select_next_server).in_sequence(redundant)
      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      @pub.expects(:select_next_server).in_sequence(redundant)
      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError).in_sequence(redundant)
      @pub.expects(:stop!).in_sequence(redundant)
      @pub.expects(:mark_server_dead).in_sequence(redundant)

      @pub.expects(:select_next_server).in_sequence(redundant)
      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 2, @pub.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "publishing should use the message ttl passed in the options hash to encode the message body" do
      data = "XXX"
      opts = {:ttl => 1.day}
      Message.expects(:encode).with(data, :ttl => 1.day)
      @pub.expects(:select_next_server)
      e = mock("exchange")
      @pub.expects(:exchange).returns(e)
      e.expects(:publish)
      assert_equal 1, @pub.publish_with_failover("mama", "mama", data, opts)
    end

    test "publishing with redundancy should use the message ttl passed in the options hash to encode the message body" do
      data = "XXX"
      opts = {:ttl => 1.day}
      Message.expects(:encode).with(data, :ttl => 1.day)
      @pub.expects(:select_next_server)
      e = mock("exchange")
      @pub.expects(:exchange).returns(e)
      e.expects(:publish)
      assert_equal 1, @pub.publish_with_redundancy("mama", "mama", data, opts)
    end

    test "publishing should use the message ttl from the message configuration if no ttl is passed in via the options hash" do
      data = "XXX"
      opts = {}
      @pub.messages["mama"] = {:ttl => 1.hour}
      @pub.expects(:publish_with_failover).with("mama", "mama", data, :ttl => 1.hour).returns(1)
      assert_equal 1, @pub.publish("mama", data)
    end
  end

  class PublisherQueueManagementTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @pub = Publisher.new(client)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @pub.queues)
      assert !@pub.queues["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @pub.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange", "key" => "haha.#")
      @pub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("Bunny")
      m.expects(:queue).with("some_queue", :durable => true).returns(q)
      @pub.expects(:bunny).returns(m)

      @pub.bind_queue("some_queue")
      assert_equal q, @pub.queues["some_queue"]
    end
  end

  class PublisherExchangeManagementTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @pub = Publisher.new(client)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @pub.exchanges_for_current_server)
      assert !@pub.exchange_exists?("some_message")
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      @pub.register_exchange("some_exchange", "type" => "topic", "durable" => true)
      m = mock("Bunny")
      m.expects(:exchange).with("some_exchange", :type => :topic, :durable => true).returns(42)
      @pub.expects(:bunny).returns(m)
      ex = @pub.exchange("some_exchange")
      assert @pub.exchange_exists?("some_exchange")
      ex2 = @pub.exchange("some_exchange")
      assert_equal ex2, ex
    end
  end

  class PublisherServerManagementTest < Test::Unit::TestCase
    def setup
      client = Client.new
      @pub = Publisher.new(client)
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
      exchange_creation = sequence("exchange creation")
      @pub.messages = []
      @pub.expects(:set_current_server).with('x').in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("a").in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("b").in_sequence(exchange_creation)
      @pub.expects(:set_current_server).with('y').in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("a").in_sequence(exchange_creation)
      @pub.expects(:create_exchange).with("b").in_sequence(exchange_creation)
      @pub.create_exchanges(messages)
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
  end
end