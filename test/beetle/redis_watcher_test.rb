require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisWatcherTest < Test::Unit::TestCase
    test "process should forward to class methods" do
      message = mock('message', :data => '{"op":"give_master", "somevariable": "somevalue"}')
      watcher = RedisWatcher.new
      watcher.stubs(:message).returns(message)
      RedisWatcher.expects(:give_master).with({"somevariable" => "somevalue"})
      watcher.process()
    end
  end

  class RedisWatcherFindActiveMasterTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      RedisWatcher.stubs(:setup_propose_check_timer)
    end

    def teardown
      RedisWatcher.alive_servers = {}
    end

    test "find_active_master should return if the current active_master if it is still active set" do
      first_working_redis      = redis_stub('redis1')
      first_working_redis.expects(:info).never
      second_working_redis     = redis_stub('redis2', :info => 'ok')

      RedisWatcher.client.deduplication_store.redis_instances = [first_working_redis, second_working_redis]
      RedisWatcher.active_master = second_working_redis
      RedisWatcher.find_active_master
      assert_equal second_working_redis, RedisWatcher.active_master
    end

    test "find_active_master should retry to reach the current master if it doesn't respond" do
      redis = redis_stub('redis')
      redis.expects(:info).times(2).raises(Timeout::Error).then.returns('ok')
      Beetle.config.redis_watcher_retry_timeout = 0.second
      Beetle.config.redis_watcher_retries       = 1
      RedisWatcher.client.deduplication_store.redis_instances = [redis]
      RedisWatcher.active_master = redis
      RedisWatcher.find_active_master
      assert_equal redis, RedisWatcher.active_master
    end

    test "find_active_master should finally give up to reach the current master after the max timeouts have been reached" do
      non_working_redis  = redis_stub('non-working-redis')
      non_working_redis.expects(:info).raises(Timeout::Error).twice
      working_redis      = redis_stub('working-redis')
      working_redis.expects(:info).returns("ok")

      Beetle.config.redis_watcher_retry_timeout   = 0.second
      Beetle.config.redis_watcher_retries         = 1
      RedisWatcher.client.deduplication_store.redis_instances = [non_working_redis, working_redis]
      RedisWatcher.active_master = non_working_redis
      RedisWatcher.find_active_master
    end

    test "find_active_master should propose the first redis it considers as working" do
      RedisWatcher.active_master = nil
      working_redis = redis_stub('working-redis', :info => "ok")
      RedisWatcher.client.deduplication_store.redis_instances = [working_redis]
      RedisWatcher.expects(:propose).with(working_redis)
      RedisWatcher.find_active_master
    end

    test "a forced change in find_active_master should start a reconfiguration run eve if there is a working redis" do
      working_redis_1 = redis_stub('working-redis_1', :info => "ok")
      working_redis_2 = redis_stub('working-redis_2', :info => "ok")
      RedisWatcher.active_master = working_redis_1
      RedisWatcher.client.deduplication_store.redis_instances = [working_redis_1, working_redis_2]
      RedisWatcher.expects(:propose).with(working_redis_2)
      RedisWatcher.find_active_master(true)
    end

    test "" do
      
    end

    test "the current master should be set to nil during the proposal phase" do
      RedisWatcher.expects(:clear_active_master)
      RedisWatcher.propose(redis_stub('new_master'))
    end

    test "clear active master should set the current master to nil" do
      RedisWatcher.active_master = "snafu"
      RedisWatcher.send(:clear_active_master)
      assert_nil RedisWatcher.active_master
    end

    test "give master should return the current master" do
      RedisWatcher.active_master = "foobar"
      assert_equal 'foobar', RedisWatcher.give_master({:server_name => 'foo'})
    end

    test "give master should set an alive timestamp for the given server" do
      assert !RedisWatcher.server_alive?('foo')
      RedisWatcher.give_master({'server_name' => 'foo'})
      assert RedisWatcher.server_alive?('foo')
    end

    test "servers that didnt ask for a server within the last 10 seconds are to be marked dead" do
      add_alive_server('bar')
      RedisWatcher.alive_servers['bar'] = Time.now - 10.seconds
      assert !RedisWatcher.server_alive?('bar')
    end
  end

  class RedisWatcherProposingTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      EM.stubs(:add_timer)
    end

    def teardown
      RedisWatcher.reset
    end

    test "proposing a new master should publish the master to the propose queue" do
      host = "my_host"
      port = "my_port"
      payload = {'host' => host, 'port' => port}
      new_master = redis_stub("new_master", payload)
      RedisWatcher.client.expects(:publish).with do |message_name, json|
        message_name == :propose && ActiveSupport::JSON.decode(json) == payload
      end
      RedisWatcher.propose(new_master)
    end

    test "propose should create a timer to check for promises" do
      EM.stubs(:add_timer).yields
      RedisWatcher.expects(:check_propose_answers)
      RedisWatcher.propose(redis_stub('new_master'))
    end

    test "propose should reset the proposal_answers" do
      assert_equal({}, RedisWatcher.send(:proposal_answers))
      add_alive_server('server1')
      RedisWatcher.proposal_answers = {'foo' => 'bar'}
      RedisWatcher.propose(redis_stub('new_master'))
      assert_equal({'server1' => nil}, RedisWatcher.send(:proposal_answers))
    end

    test "all_alive_servers_promised? should return false if no alive server promised for the new server" do
      add_alive_server('server1')
      new_master = redis_stub('new_master')
      RedisWatcher.propose(new_master)
      assert !RedisWatcher.send(:all_alive_servers_promised?, new_master)
    end

    test "all_alive_servers_promised? should return true if all alive server promised for the new server" do
      add_alive_server('server1')
      add_alive_server('server2')
      new_master = redis_stub('new_master')
      RedisWatcher.promise({'sender_name' => 'server1', 'acked_server' => new_master.server})
      RedisWatcher.promise({'sender_name' => 'server2', 'acked_server' => new_master.server})
      assert RedisWatcher.send(:all_alive_servers_promised?, new_master)
    end


    test "check_propose_answers should setup a new timer if not every server has answered" do
      new_master = redis_stub('new_master')
      EM.expects(:add_timer).twice.yields
      RedisWatcher.stubs(:reconfigure)
      RedisWatcher.expects(:all_alive_servers_promised?).twice.returns(false).then.returns(true)
      RedisWatcher.propose(new_master)
    end

    test "check_propose_answers should stop checking and repropose after xx retries" do
      # flunk <<-GRUEBEL
      # what happens in between?
      # What if a client timed out already?
      # How to keep clients alive in that phase?
      # GRUEBEL
    end

    test "proposing a new master should set the current master to nil" do
      RedisWatcher.active_master = redis_stub('current master')
      assert RedisWatcher.active_master
      new_master = redis_stub('new master')
      RedisWatcher.propose(new_master)
      assert_equal nil, RedisWatcher.active_master
    end

    test "proposing a new master should give the order to reconfigure if every server accepted the proposal" do
      new_master = redis_stub('new_master')
      EM.stubs(:add_timer).yields
      RedisWatcher.stubs(:all_alive_servers_promised?).returns(true)
      RedisWatcher.expects(:reconfigure).with(new_master)
      RedisWatcher.propose(new_master)
    end

  end

  class RedisWatcherReconfigurationTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      EM.stubs(:add_timer)
    end

    test "the reconfigure method should publish the reconfigure message with the new master data" do
      redis_options = {'host' => 'foobar', 'port' => '1234'}
      new_master    = redis_stub('new_master', redis_options)
      RedisWatcher.client.expects(:publish).with do |message_name, json|
        message_name == :reconfigure && ActiveSupport::JSON.decode(json) == redis_options
      end
      RedisWatcher.reconfigure(new_master)
    end

    test "the reconfigure method should start the setup_reconfigured_check_timer" do
      new_master    = redis_stub('new_master')
      RedisWatcher.expects(:setup_reconfigured_check_timer).with(new_master)
      RedisWatcher.reconfigure(new_master)
    end

    test "the reconfigure check timer should setup a timer to check wether all workers have answered properly" do
      new_master    = redis_stub('new_master')
      RedisWatcher.client.config.redis_watcher_propose_timer = 12
      EM.expects(:add_timer).with(12).yields
      RedisWatcher.expects(:check_reconfigured_answers)
      RedisWatcher.send(:setup_reconfigured_check_timer, new_master)
    end
    
    test "check_reconfigured_answers should "

    test "the all_alive_servers_reconfigured? should return true if all workers have answered properly" do
      
    end

  end

end

