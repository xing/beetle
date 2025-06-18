require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class PublisherTest < Minitest::Test
    def setup
      @client = Client.new
      @pub = Publisher.new(@client)
    end

    test "acccessing a bunny for a server which doesn't have one should create it and associate it with the server" do
      @pub.expects(:new_bunny).returns(42)
      assert_equal 42, @pub.send(:bunny)
      bunnies = @pub.instance_variable_get("@bunnies")
      assert_equal(42, bunnies[@pub.server])
    end

    test "new bunnies should be created using current host and port and they should be started" do
      m = mock("dummy")
      expected_bunny_options = {
        :host => @pub.send(:current_host),
        :port => @pub.send(:current_port),
        :logger => @client.config.logger,
        :username => "guest",
        :password => "guest",
        :vhost => "/",
        :automatically_recover => false,
        :recovery_attempts => nil,
        :read_timeout => 5,
        :write_timeout => 5,
        :continuation_timeout => 5_000,
        :connection_timeout => 5,
        :frame_max => 131072,
        :channel_max => 2047,
        :heartbeat => :server,
        :tls => false
      }
      Bunny.expects(:new).with { |actual| expected_bunny_options.all? { |k, v| actual[k] == v } }.returns(m)
      m.expects(:start)
      assert_equal m, @pub.send(:new_bunny)
    end

    test "new bunnies should be created using custom connection options and they should be started" do
      config = Configuration.new
      config.servers = 'localhost:5672'
      config.server_connection_options["localhost:5672"] = { user: "john", pass: "doe", vhost: "test", ssl: false }
      client = Client.new(config)
      pub = Publisher.new(client)

      bunny_mock = mock("dummy_bunny")
      expected_bunny_options = {
        host: "localhost",
        port: 5672,
        username: "john",
        password: "doe",
        vhost: "test",
        tls: false,
        automatically_recover: false,
        :recovery_attempts => nil,
        read_timeout: 5,
        write_timeout: 5,
        continuation_timeout: 5_000,
        connection_timeout: 5,
        channel_max: 2047,
        heartbeat: :server
      }

      Bunny
        .expects(:new)
        .with { |actual| expected_bunny_options.all? { |k, v| actual[k] == v }  } # match our subset of options
        .returns(bunny_mock)
      bunny_mock.expects(:start)
      assert_equal bunny_mock, pub.send(:new_bunny)
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
      @pub.expects(:bunny?).returns(true)
      @pub.expects(:bunny).returns(b)
      @pub.send(:stop!)
      assert_equal({}, @pub.send(:exchanges))
      assert_equal({}, @pub.send(:queues))
      assert_nil @pub.instance_variable_get(:@bunnies)[@pub.server]
      assert_nil @pub.instance_variable_get(:@channels)[@pub.server]
    end

    test "stop!(exception) should close the bunny socket if an exception is not nil" do
      b = mock("bunny")
      l = mock("loop")
      b.expects(:close_connection)
      b.expects(:reader_loop).returns(l)
      l.expects(:kill)
      @pub.expects(:bunny?).returns(true)
      @pub.expects(:bunny).returns(b).twice
      @pub.send(:stop!, Exception.new)
      assert_equal({}, @pub.send(:exchanges))
      assert_equal({}, @pub.send(:queues))
      assert_nil @pub.instance_variable_get(:@bunnies)[@pub.server]
      assert_nil @pub.instance_variable_get(:@channels)[@pub.server]
    end

    test "stop! should not create a new bunny " do
      @pub.expects(:bunny?).returns(false)
      @pub.expects(:bunny).never
      @pub.send(:stop!)
      assert_equal({}, @pub.send(:exchanges))
      assert_equal({}, @pub.send(:queues))
      assert_nil @pub.instance_variable_get(:@bunnies)[@pub.server]
      assert_nil @pub.instance_variable_get(:@channels)[@pub.server]
    end

  end

  class PublisherPublishingTest < Minitest::Test
    def setup
      @config = Configuration.new
      @config.servers = ENV['RABBITMQ_SERVERS'].split(',').first if ENV['RABBITMQ_SERVERS']
      @client = Client.new(@config)
      @pub = Publisher.new(@client)
      @pub.stubs(:bind_queues_for_exchange)
      @client.register_queue("mama", :exchange => "mama-exchange")
      @client.register_message("mama", :ttl => 1.hour, :exchange => "mama-exchange")
      @opts = { :ttl => 1.hour , :key => "mama", :persistent => true}
      @data = 'XXX'
    end

    test "failover publishing should try to recycle dead servers before trying to publish the message" do
      @pub.servers << "localhost:3333"
      @pub.send(:mark_server_dead)
      publishing = sequence('publishing')
      @pub.expects(:recycle_dead_servers).in_sequence(publishing)
      @pub.expects(:throttle!).in_sequence(publishing)
      @pub.expects(:publish_with_failover).with("mama-exchange", "mama", @data, @opts).in_sequence(publishing)
      @pub.publish("mama", @data)
    end

    test "redundant publishing should try to recycle dead servers before trying to publish the message" do
      @pub.servers << "localhost:3333"
      @pub.send(:mark_server_dead)
      publishing = sequence('publishing')
      @pub.expects(:recycle_dead_servers).in_sequence(publishing)
      @pub.expects(:throttle!).in_sequence(publishing)
      @pub.expects(:publish_with_redundancy).with("mama-exchange", "mama", @data, @opts.merge(:redundant => true)).in_sequence(publishing)
      @pub.publish("mama", @data, :redundant => true)
    end

    test "publishing should fail over to the next server" do
      @pub.servers << "localhost:3333"
      raising_exchange = mock("raising exchange")
      nice_exchange = mock("nice exchange")
      @pub.stubs(:exchange).with("mama-exchange").returns(raising_exchange).then.returns(raising_exchange).then.returns(nice_exchange)

      raising_exchange.expects(:publish).raises(Bunny::ConnectionError, '').twice
      nice_exchange.expects(:publish)
      @pub.expects(:set_current_server).twice
      @pub.expects(:stop!).twice
      @pub.expects(:mark_server_dead).once
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
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 1, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should raise an exception if the message was published to no server" do
      redundant = sequence("redundant")
      @pub.servers = ["someserver", "someotherserver"]
      @pub.server = "someserver"

      e = mock("exchange")
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(redundant)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(redundant)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(redundant)

      assert_raises Beetle::NoMessageSent do
        @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
      end
    end

    test "redundant publishing should fallback to failover publishing if less than one server is available" do
      @pub.server = ["a server"]
      @pub.expects(:publish_with_failover).with("mama-exchange", "mama", @data, @opts).returns(1)
      assert_equal 1, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should remove redundant flag if less than two servers are available" do
      @pub.servers = ["a server"]
      @pub.server = "a server"
      @pub.expects(:publish_with_failover).with("mama-exchange", "mama", @data, @opts.merge(redundant: false)).returns(1)
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
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(redundant)
      @pub.expects(:stop!).in_sequence(redundant)

      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 2, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should log a warning if only one server is active" do
      @pub.servers = %w(server1 server2)
      @pub.server = "server1"
      @pub.send :mark_server_dead

      redundant = sequence("redundant")
      e = mock("exchange")

      @pub.logger.expects(:warn).with("Beetle: at least two active servers are required for redundant publishing")

      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 1, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end

    test "redundant publishing should not log a warning if only one server exists" do
      @pub.servers = %w(server1)
      @pub.server = "server1"

      redundant = sequence("redundant")
      e = mock("exchange")

      @pub.logger.expects(:warn).with("Beetle: at least two active servers are required for redundant publishing").never

      @pub.expects(:exchange).returns(e).in_sequence(redundant)
      e.expects(:publish).in_sequence(redundant)

      assert_equal 1, @pub.publish_with_redundancy("mama-exchange", "mama", @data, @opts)
    end


    test "publishing should use the message ttl passed in the options hash to encode the message body" do
      opts = {:ttl => 1.day}
      Message.expects(:publishing_options).with(:ttl => 1.day).returns({})
      @pub.expects(:select_next_server)
      e = mock("exchange")
      @pub.expects(:exchange).returns(e)
      e.expects(:publish)
      assert_equal 1, @pub.publish_with_failover("mama-exchange", "mama", @data, opts)
    end

    test "publishing with redundancy should use the message ttl passed in the options hash to encode the message body" do
      opts = {:ttl => 1.day}
      Message.expects(:publishing_options).with(:ttl => 1.day, redundant: false).returns({})
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

    test "failover publishing should raise an exception if the message was published to no server" do
      failover = sequence("failover")
      @pub.servers = ["someserver", "someotherserver"]
      @pub.server = "someserver"

      e = mock("exchange")
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(failover)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(failover)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(failover)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(failover)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(failover)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(failover)
      @pub.expects(:exchange).with("mama-exchange").returns(e).in_sequence(failover)
      e.expects(:publish).raises(Bunny::ConnectionError, '').in_sequence(failover)

      assert_raises Beetle::NoMessageSent do
        @pub.publish_with_failover("mama-exchange", "mama", @data, @opts)
      end
    end

  end

  class PublisherQueueManagementTest < Minitest::Test
    def setup
      @config = Configuration.new
      @config.servers = ENV['RABBITMQ_SERVERS'] if ENV['RABBITMQ_SERVERS']
      @client = Client.new(@config)
      @pub = Publisher.new(@client)
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @pub.send(:queues))
      assert !@pub.send(:queues)["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @client.register_queue("some_queue", :exchange => "some_exchange", :key => "haha.#", :arguments => {"foo" => "fighter"})
      @pub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      @pub.expects(:publish_policy_options)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("Bunny")
      channel= mock("channel")
      m.expects(:create_channel).returns(channel)
      channel.expects(:queue).with("some_queue", :durable => true, :passive => false, :auto_delete => false, :exclusive => false, :arguments => {"foo" => "fighter"}).returns(q)
      @pub.expects(:bunny).returns(m)

      @pub.send(:queue, "some_queue")
      assert_equal q, @pub.send(:queues)["some_queue"]
    end

    test "should bind the defined queues for the used exchanges when publishing" do
      @client.register_queue('test_queue_1', :exchange => 'test_exchange')
      @client.register_queue('test_queue_2', :exchange => 'test_exchange')
      @client.register_queue('test_queue_3', :exchange => 'test_exchange_2')
      queue = mock("queue")
      @pub.expects(:bind_queue!).with(queue, "test_exchange", {:key => "test_queue_1"}).once
      @pub.expects(:bind_queue!).with(queue, "test_exchange", {:key => "test_queue_2"}).once
      @pub.expects(:bind_queue!).with(queue, "test_exchange_2", {:key => "test_queue_3"}).once
      @pub.expects(:declare_queue!).returns(queue).times(3)
      @pub.send(:bind_queues_for_exchange, 'test_exchange')
      @pub.send(:bind_queues_for_exchange, 'test_exchange_2')
    end

    test "when lazy_queue_setup is fals it does not bind queues for the used  exchange when publishing" do
      @client.register_queue('test_queue_1', :exchange => 'test_exchange')
      @client.register_queue('test_queue_2', :exchange => 'test_exchange')
      @client.register_queue('test_queue_3', :exchange => 'test_exchange_2')
      @client.register_message("mama", :ttl => 1.hour, :exchange => "mama-exchange")

      begin
        @client.config.publisher_lazy_queue_setup = false
        exchange = mock("exchange")
        exchange.expects(:publish).returns(nil)

        @pub.expects(:exchange).with("mama-exchange").returns(exchange)
        @pub.expects(:declare_queue!).never
        @pub.expects(:bind_queue!).never
        @pub.publish('mama', "XXX")
      ensure
        @client.config.publisher_lazy_queue_setup = true
      end
    end

    test "should not rebind the defined queues for the used exchanges if they already have been bound" do
      @client.register_queue('test_queue_1', :exchange => 'test_exchange')
      @client.register_queue('test_queue_2', :exchange => 'test_exchange')
      queue = mock("queue")
      @pub.expects(:declare_queue!).returns(queue).twice
      @pub.expects(:bind_queue!).with(queue, "test_exchange", {:key => "test_queue_1"}).once
      @pub.expects(:bind_queue!).with(queue, "test_exchange", {:key => "test_queue_2"}).once
      @pub.send(:bind_queues_for_exchange, 'test_exchange')
      @pub.send(:bind_queues_for_exchange, 'test_exchange')
    end

    test "should declare queues only once even with many bindings" do

      @client.register_queue('test_queue', :exchange => 'test_exchange')
      @client.register_binding('test_queue', :exchange => 'test_exchange', :key => 'sir-message-a-lot')
      queue = mock("queue")
      @pub.expects(:declare_queue!).returns(queue).once
      @pub.expects(:bind_queue!).with(queue, "test_exchange", {:key => "test_queue"}).once
      @pub.expects(:bind_queue!).with(queue, "test_exchange", {:key => "sir-message-a-lot"}).once
      @pub.send(:bind_queues_for_exchange, 'test_exchange')
    end

    test "call the queue binding method when publishing" do
      data = "XXX"
      opts = {}
      @client.register_queue("mama", :exchange => "mama-exchange")
      @client.register_message("mama", :ttl => 1.hour, :exchange => "mama-exchange")
      e = stub('exchange', 'publish')
      @pub.expects(:exchange).with('mama-exchange').returns(e)
      @pub.expects(:bind_queues_for_exchange).with('mama-exchange').returns(true)
      @pub.publish('mama', data)
    end

    test "purging a queue should purge the queues on all servers" do
      @pub.servers = %w(a b)
      queue = mock("queue")
      s = sequence("purging")
      @pub.expects(:set_current_server).with("a").in_sequence(s)
      @pub.expects(:queue).with("queue").returns(queue).in_sequence(s)
      queue.expects(:purge).in_sequence(s)
      @pub.expects(:set_current_server).with("b").in_sequence(s)
      @pub.expects(:queue).with("queue").returns(queue).in_sequence(s)
      queue.expects(:purge).in_sequence(s)
      @pub.purge(["queue"])
    end

    test "setting up queues and policies should iterate over all servers" do
      client = Client.new
      client.register_queue("queue")
      pub = Publisher.new(client)
      pub.servers = %w(a b)

      s = sequence("setup")
      pub.expects(:set_current_server).with("a").in_sequence(s)
      pub.expects(:queue).with(client.config.beetle_policy_updates_queue_name).in_sequence(s)
      pub.expects(:queue).with("queue").in_sequence(s)
      pub.expects(:set_current_server).with("b").in_sequence(s)
      pub.expects(:queue).with(client.config.beetle_policy_updates_queue_name).in_sequence(s)
      pub.expects(:queue).with("queue").in_sequence(s)

      pub.setup_queues_and_policies()
    end

    test "setting up queues and policies should handle ephemeral errors" do
      client = Client.new
      pub = Publisher.new(client)
      client.register_queue("queue")
      pub.servers = %w(a b)
      pub.stubs(:queue).raises(StandardError)

      s = sequence("setup")
      pub.expects(:set_current_server).with("a").in_sequence(s)
      pub.expects(:set_current_server).with("b").in_sequence(s)

      pub.setup_queues_and_policies()
    end

    test "reports whether it has been throttled" do
      assert !@pub.throttled?
      @pub.instance_variable_set :@throttled, true
      assert @pub.throttled?
    end

    test "sets throttling options" do
      h = { "x" => 1, "y" => 2}
      @pub.throttle(h)
      assert_equal h, @pub.instance_variable_get(:@throttling_options)
    end

    test "throttle! sleeps appropriately when refreshing throttling" do
      @pub.expects(:throttling?).returns(true).twice
      @pub.expects(:refresh_throttling!).twice
      @pub.expects(:throttled?).returns(true)
      @pub.expects(:sleep).with(1)
      @pub.throttle!
      @pub.expects(:throttled?).returns(false)
      @pub.expects(:sleep).never
      @pub.throttle!
    end

    test "returns a throttling status" do
      assert_equal 'unthrottled', @pub.throttling_status
      @pub.instance_variable_set :@throttled, true
      assert_equal 'throttled', @pub.throttling_status
    end

    test "refresh_throttling! does not recompute values when refresh interval has not passed" do
      @pub.instance_variable_set :@next_throttle_refresh, Time.now + 1
      options = {}
      @pub.throttle(options)
      options.expects(:each).never
      @pub.__send__ :refresh_throttling!
    end

    test "refresh_throttling! throttles when queue length exceeds limit" do
      assert !@pub.throttled?
      @pub.instance_variable_set :@next_throttle_refresh, Time.now - 1
      options = { "test" => 100 }
      @pub.throttle(options)
      @pub.expects(:each_server).yields
      q = mock("queue")
      q.expects(:status).returns(:message_count => 500)
      @pub.expects(:queue).returns(q)
      @pub.logger.expects(:info)
      @pub.__send__ :refresh_throttling!
      assert @pub.throttled?
    end

    test "refresh_throttling! logs a warning if an exception is raised during throttling" do
      assert !@pub.throttled?
      @pub.instance_variable_set :@next_throttle_refresh, Time.now - 1
      options = { "test" => 100 }
      @pub.throttle(options)
      @pub.expects(:each_server).raises(StandardError.new("foo"))
      @pub.logger.expects(:warn)
      @pub.__send__ :refresh_throttling!
      assert !@pub.throttled?
    end

  end

  class PublisherExchangeManagementTest < Minitest::Test
    def setup
      @client = Client.new
      @pub = Publisher.new(@client)
    end

    test "initially there should be no exchanges for the current server" do
      assert_equal({}, @pub.send(:exchanges))
    end

    test "accessing a given exchange should create it using the config. further access should return the created exchange" do
      bunny = mock("bunny")
      channel = mock("channel")
      channel.expects(:exchange).with("some_exchange", :type => :topic, :durable => true, :queues => []).returns(42)
      @client.register_exchange("some_exchange", :type => :topic, :durable => true)
      @pub.expects(:bunny).returns(bunny)
      bunny.expects(:create_channel).returns(channel)
      ex  = @pub.send(:exchange, "some_exchange")
      assert @pub.send(:exchanges).include?("some_exchange")
      ex2 = @pub.send(:exchange, "some_exchange")
      assert_equal ex2, ex
    end
  end

  class PublisherServerManagementTest < Minitest::Test
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

    test "recycle_dead_servers should move servers from the dead server hash to the servers list only if they have been markd dead for longer than 10 seconds" do
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

    test "recycle_dead_servers should recycle the server which has been dead for the longest time if all servers are dead " do
      @pub.servers = ["a:1", "b:2"]
      @pub.send(:set_current_server, "a:1")
      @pub.send(:mark_server_dead)
      @pub.send(:mark_server_dead)
      assert_equal [], @pub.servers
      dead = @pub.instance_variable_get("@dead_servers")
      assert_equal ["a:1", "b:2"], dead.keys.sort
      @pub.send(:recycle_dead_servers)
      assert_equal ["b:2"], dead.keys
      assert_equal ["a:1"], @pub.servers
    end

    test "select_next_server should cycle through the list of all servers" do
      @pub.servers = ["a:1", "b:2"]
      @pub.send(:set_current_server, "a:1")
      @pub.send(:select_next_server)
      assert_equal "b:2", @pub.server
      @pub.send(:select_next_server)
      assert_equal "a:1", @pub.server
    end

    test "select_next_server should log an error if there are no servers to publish to" do
      @pub.servers = []
      logger = mock('logger')
      logger.expects(:debug).with("Selected new server for publishing:#{@pub.server}.\n Dead servers are none")
      logger.expects(:error).returns(true)
      @pub.expects(:logger).twice.returns(logger)
      @pub.expects(:set_current_server).never
      @pub.send(:select_next_server)
    end

    test "stop should shut down all bunnies" do
      @pub.servers = ["localhost:1111", "localhost:2222"]
      s = sequence("shutdown")
      bunny1 = mock("bunny1")
      bunny2 = mock("bunny2")
      @pub.expects(:set_current_server).with("localhost:1111").in_sequence(s)
      @pub.expects(:bunny?).returns(true).in_sequence(s)
      @pub.expects(:bunny).returns(bunny1).in_sequence(s)
      bunny1.expects(:stop).in_sequence(s)
      @pub.expects(:set_current_server).with("localhost:2222").in_sequence(s)
      @pub.expects(:bunny?).returns(true).in_sequence(s)
      @pub.expects(:bunny).returns(bunny2).in_sequence(s)
      bunny2.expects(:stop).in_sequence(s)
      @pub.stop
    end
  end

  class PublisherPublishingWithConfirmTest < Minitest::Test
    def setup
      @config = Configuration.new
      @config.servers = ENV['RABBITMQ_SERVERS'].split(',').first if ENV['RABBITMQ_SERVERS']
      @config.publisher_confirms = true
      @client = Client.new(@config)
      @pub = Publisher.new(@client)
      @pub.stubs(:bind_queues_for_exchange)
      @client.register_queue("mama", :exchange => "mama-exchange")
      @client.register_message("mama", :ttl => 1.hour, :exchange => "mama-exchange")
      @opts = { :ttl => 1.hour , :key => "mama", :persistent => false}
      @data = 'XXX'
    end

    test "should wait for publisher confirms" do
      confirms_sequence = sequence("confirms")
      @pub.servers = ["someserver"]
      @pub.server = "someserver"

      exchange = mock("exchange")

      @pub.expects(:exchange).with("mama-exchange").returns(exchange).in_sequence(confirms_sequence)
      exchange.expects(:publish).in_sequence(confirms_sequence)
      exchange.expects(:wait_for_confirms).returns(true).in_sequence(confirms_sequence)

      assert_equal 1, @pub.publish("mama", @data, @opts)
    end

    test "should raise an exception when confirms return false" do
      confirms_sequence = sequence("confirms")
      @pub.servers = ["someserver"]
      @pub.server = "someserver"

      exchange = mock("exchange")

      @pub.expects(:exchange).with("mama-exchange").returns(exchange).in_sequence(confirms_sequence)
      exchange.expects(:publish).in_sequence(confirms_sequence)
      exchange.expects(:wait_for_confirms).returns(false).in_sequence(confirms_sequence)

      assert_equal 0, @pub.publish("mama", @data, @opts)
    end

    test "if the confirm is enabled for channel the confirm select is not called second time" do
      confirms_sequence = sequence("confirms")
      @pub.servers = ["someserver"]
      @pub.server = "someserver"
      exchange = mock("exchange")

      @pub.expects(:exchange).with("mama-exchange").returns(exchange).in_sequence(confirms_sequence)
      exchange.expects(:publish).in_sequence(confirms_sequence)
      exchange.expects(:wait_for_confirms).returns(true).in_sequence(confirms_sequence)
      assert_equal 1, @pub.publish("mama", @data, @opts)
    end
  end
end
