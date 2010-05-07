require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationServerTest < Test::Unit::TestCase
    test "process should forward to class methods" do
      message = mock('message', :data => '{"op":"give_master", "somevariable": "somevalue"}')
      watcher = RedisConfigurationServer.new
      watcher.stubs(:message).returns(message)
      RedisConfigurationServer.expects(:give_master).with({"somevariable" => "somevalue"})
      watcher.process()
    end
  end

  class RedisConfigurationServerFindActiveMasterTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      RedisConfigurationServer.stubs(:setup_propose_check_timer)
    end

    def teardown
      RedisConfigurationServer.alive_servers = {}
    end

    test "find_active_master should return if the current active_master if it is still active set" do
      first_working_redis      = redis_stub('redis1')
      first_working_redis.expects(:info).never
      second_working_redis     = redis_stub('redis2', :info => 'ok')

      RedisConfigurationServer.client.deduplication_store.redis_instances = [first_working_redis, second_working_redis]
      RedisConfigurationServer.active_master = second_working_redis
      RedisConfigurationServer.find_active_master
      assert_equal second_working_redis, RedisConfigurationServer.active_master
    end

    test "find_active_master should retry to reach the current master if it doesn't respond" do
      redis = redis_stub('redis')
      redis.expects(:info).times(2).raises(Timeout::Error).then.returns('ok')
      Beetle.config.redis_watcher_retry_timeout = 0.second
      Beetle.config.redis_watcher_retries       = 1
      RedisConfigurationServer.client.deduplication_store.redis_instances = [redis]
      RedisConfigurationServer.active_master = redis
      RedisConfigurationServer.find_active_master
      assert_equal redis, RedisConfigurationServer.active_master
    end

    test "find_active_master should finally give up to reach the current master after the max timeouts have been reached" do
      non_working_redis  = redis_stub('non-working-redis')
      non_working_redis.expects(:info).raises(Timeout::Error).twice
      working_redis      = redis_stub('working-redis')
      working_redis.expects(:info).returns("ok")

      Beetle.config.redis_watcher_retry_timeout   = 0.second
      Beetle.config.redis_watcher_retries         = 1
      RedisConfigurationServer.client.deduplication_store.redis_instances = [non_working_redis, working_redis]
      RedisConfigurationServer.active_master = non_working_redis
      RedisConfigurationServer.find_active_master
    end

    test "find_active_master should propose the first redis it considers as working" do
      RedisConfigurationServer.active_master = nil
      working_redis = redis_stub('working-redis', :info => "ok")
      RedisConfigurationServer.client.deduplication_store.redis_instances = [working_redis]
      RedisConfigurationServer.expects(:propose).with(working_redis)
      RedisConfigurationServer.find_active_master
    end

    test "a forced change in find_active_master should start a reconfiguration run eve if there is a working redis" do
      working_redis_1 = redis_stub('working-redis_1', :info => "ok")
      working_redis_2 = redis_stub('working-redis_2', :info => "ok")
      RedisConfigurationServer.active_master = working_redis_1
      RedisConfigurationServer.client.deduplication_store.redis_instances = [working_redis_1, working_redis_2]
      RedisConfigurationServer.expects(:propose).with(working_redis_2)
      RedisConfigurationServer.find_active_master(true)
    end

    test "" do
      
    end

    test "the current master should be set to nil during the proposal phase" do
      RedisConfigurationServer.expects(:clear_active_master)
      RedisConfigurationServer.propose(redis_stub('new_master'))
    end

    test "clear active master should set the current master to nil" do
      RedisConfigurationServer.active_master = "snafu"
      RedisConfigurationServer.send(:clear_active_master)
      assert_nil RedisConfigurationServer.active_master
    end

    test "give master should return the current master" do
      RedisConfigurationServer.active_master = "foobar"
      assert_equal 'foobar', RedisConfigurationServer.give_master({:server_name => 'foo'})
    end

    test "give master should set an alive timestamp for the given server" do
      assert !RedisConfigurationServer.server_alive?('foo')
      RedisConfigurationServer.give_master({'server_name' => 'foo'})
      assert RedisConfigurationServer.server_alive?('foo')
    end

    test "servers that didnt ask for a server within the last 10 seconds are to be marked dead" do
      add_alive_server('bar')
      RedisConfigurationServer.alive_servers['bar'] = Time.now - 10.seconds
      assert !RedisConfigurationServer.server_alive?('bar')
    end
  end

  class RedisConfigurationServerProposingTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      EM.stubs(:add_timer)
    end

    def teardown
      RedisConfigurationServer.reset
    end

    test "proposing a new master should publish the master to the propose queue" do
      host = "my_host"
      port = "my_port"
      payload = {'host' => host, 'port' => port}
      new_master = redis_stub("new_master", payload)
      RedisConfigurationServer.client.expects(:publish).with do |message_name, json|
        message_name == :propose && ActiveSupport::JSON.decode(json) == payload
      end
      RedisConfigurationServer.propose(new_master)
    end

    test "propose should create a timer to check for promises" do
      EM.stubs(:add_timer).yields
      RedisConfigurationServer.expects(:check_propose_answers)
      RedisConfigurationServer.propose(redis_stub('new_master'))
    end

    test "propose should reset the proposal_answers" do
      assert_equal({}, RedisConfigurationServer.send(:proposal_answers))
      add_alive_server('server1')
      RedisConfigurationServer.proposal_answers = {'foo' => 'bar'}
      RedisConfigurationServer.propose(redis_stub('new_master'))
      assert_equal({'server1' => nil}, RedisConfigurationServer.send(:proposal_answers))
    end

    test "all_alive_servers_promised? should return false if no alive server promised for the new server" do
      add_alive_server('server1')
      new_master = redis_stub('new_master')
      RedisConfigurationServer.propose(new_master)
      assert !RedisConfigurationServer.send(:all_alive_servers_promised?, new_master)
    end

    test "all_alive_servers_promised? should return true if all alive server promised for the new server" do
      add_alive_server('server1')
      add_alive_server('server2')
      new_master = redis_stub('new_master')
      RedisConfigurationServer.promise({'sender_name' => 'server1', 'acked_server' => new_master.server})
      RedisConfigurationServer.promise({'sender_name' => 'server2', 'acked_server' => new_master.server})
      assert RedisConfigurationServer.send(:all_alive_servers_promised?, new_master)
    end


    test "check_propose_answers should setup a new timer if not every server has answered" do
      new_master = redis_stub('new_master')
      EM.expects(:add_timer).twice.yields
      RedisConfigurationServer.stubs(:reconfigure)
      RedisConfigurationServer.expects(:all_alive_servers_promised?).twice.returns(false).then.returns(true)
      RedisConfigurationServer.propose(new_master)
    end

    test "check_propose_answers should stop checking and repropose after xx retries" do
      # flunk <<-GRUEBEL
      # what happens in between?
      # What if a client timed out already?
      # How to keep clients alive in that phase?
      # GRUEBEL
    end

    test "proposing a new master should set the current master to nil" do
      RedisConfigurationServer.active_master = redis_stub('current master')
      assert RedisConfigurationServer.active_master
      new_master = redis_stub('new master')
      RedisConfigurationServer.propose(new_master)
      assert_equal nil, RedisConfigurationServer.active_master
    end

    test "proposing a new master should give the order to reconfigure if every server accepted the proposal" do
      new_master = redis_stub('new_master')
      EM.stubs(:add_timer).yields
      RedisConfigurationServer.stubs(:all_alive_servers_promised?).returns(true)
      RedisConfigurationServer.expects(:reconfigure).with(new_master)
      RedisConfigurationServer.propose(new_master)
    end

  end

  class RedisConfigurationServerReconfigurationTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      EM.stubs(:add_timer)
    end

    test "the reconfigure method should publish the reconfigure message with the new master data" do
      redis_options = {'host' => 'foobar', 'port' => '1234'}
      new_master    = redis_stub('new_master', redis_options)
      RedisConfigurationServer.client.expects(:publish).with do |message_name, json|
        message_name == :reconfigure && ActiveSupport::JSON.decode(json) == redis_options
      end
      RedisConfigurationServer.reconfigure(new_master)
    end

    test "the reconfigure method should start the setup_reconfigured_check_timer" do
      new_master    = redis_stub('new_master')
      RedisConfigurationServer.expects(:setup_reconfigured_check_timer).with(new_master)
      RedisConfigurationServer.reconfigure(new_master)
    end

    test "the reconfigure check timer should setup a timer to check wether all workers have answered properly" do
      new_master    = redis_stub('new_master')
      RedisConfigurationServer.client.config.redis_watcher_propose_timer = 12
      EM.expects(:add_timer).with(12).yields
      RedisConfigurationServer.expects(:check_reconfigured_answers)
      RedisConfigurationServer.send(:setup_reconfigured_check_timer, new_master)
    end
    
    test "the all_alive_servers_reconfigured? should return true if all workers have answered properly" do
      flunk      
    end

  end

end

