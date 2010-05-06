require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisCoordinatorTest < Test::Unit::TestCase
    test "process should forward to class methods" do
      message = mock('message', :data => '{"op":"give_master", "somevariable": "somevalue"}')
      watcher = RedisCoordinator.new
      watcher.stubs(:message).returns(message)
      RedisCoordinator.expects(:give_master).with({"somevariable" => "somevalue"})
      watcher.process()
    end
  end

  class RedisCoordinatorFindActiveMasterTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      RedisCoordinator.stubs(:setup_propose_check_timer)
    end

    def teardown
      RedisCoordinator.alive_servers = {}
    end

    test "find_active_master should return if the current active_master if it is still active set" do
      first_working_redis      = redis_stub('redis1')
      first_working_redis.expects(:info).never
      second_working_redis     = redis_stub('redis2', :info => 'ok')

      RedisCoordinator.client.deduplication_store.redis_instances = [first_working_redis, second_working_redis]
      RedisCoordinator.active_master = second_working_redis
      RedisCoordinator.find_active_master
      assert_equal second_working_redis, RedisCoordinator.active_master
    end

    test "find_active_master should retry to reach the current master if it doesn't respond" do
      redis = redis_stub('redis')
      redis.expects(:info).times(2).raises(Timeout::Error).then.returns('ok')
      Beetle.config.redis_watcher_retry_timeout = 0.second
      Beetle.config.redis_watcher_retries       = 1
      RedisCoordinator.client.deduplication_store.redis_instances = [redis]
      RedisCoordinator.active_master = redis
      RedisCoordinator.find_active_master
      assert_equal redis, RedisCoordinator.active_master
    end

    test "find_active_master should finally give up to reach the current master after the max timeouts have been reached" do
      non_working_redis  = redis_stub('non-working-redis')
      non_working_redis.expects(:info).raises(Timeout::Error).twice
      working_redis      = redis_stub('working-redis')
      working_redis.expects(:info).returns("ok")

      Beetle.config.redis_watcher_retry_timeout   = 0.second
      Beetle.config.redis_watcher_retries         = 1
      RedisCoordinator.client.deduplication_store.redis_instances = [non_working_redis, working_redis]
      RedisCoordinator.active_master = non_working_redis
      RedisCoordinator.find_active_master
    end

    test "find_active_master should propose the first redis it considers as working" do
      RedisCoordinator.active_master = nil
      working_redis = redis_stub('working-redis', :info => "ok")
      RedisCoordinator.client.deduplication_store.redis_instances = [working_redis]
      RedisCoordinator.expects(:propose).with(working_redis)
      RedisCoordinator.find_active_master
    end

    test "a forced change in find_active_master should start a reconfiguration run eve if there is a working redis" do
      working_redis_1 = redis_stub('working-redis_1', :info => "ok")
      working_redis_2 = redis_stub('working-redis_2', :info => "ok")
      RedisCoordinator.active_master = working_redis_1
      RedisCoordinator.client.deduplication_store.redis_instances = [working_redis_1, working_redis_2]
      RedisCoordinator.expects(:propose).with(working_redis_2)
      RedisCoordinator.find_active_master(true)
    end

    test "" do
      
    end

    test "the current master should be set to nil during the proposal phase" do
      RedisCoordinator.expects(:clear_active_master)
      RedisCoordinator.propose(redis_stub('new_master'))
    end

    test "clear active master should set the current master to nil" do
      RedisCoordinator.active_master = "snafu"
      RedisCoordinator.send(:clear_active_master)
      assert_nil RedisCoordinator.active_master
    end

    test "give master should return the current master" do
      RedisCoordinator.active_master = "foobar"
      assert_equal 'foobar', RedisCoordinator.give_master({:server_name => 'foo'})
    end

    test "give master should set an alive timestamp for the given server" do
      assert !RedisCoordinator.server_alive?('foo')
      RedisCoordinator.give_master({'server_name' => 'foo'})
      assert RedisCoordinator.server_alive?('foo')
    end

    test "servers that didnt ask for a server within the last 10 seconds are to be marked dead" do
      add_alive_server('bar')
      RedisCoordinator.alive_servers['bar'] = Time.now - 10.seconds
      assert !RedisCoordinator.server_alive?('bar')
    end
  end

  class RedisCoordinatorProposingTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      EM.stubs(:add_timer)
    end

    def teardown
      RedisCoordinator.reset
    end

    test "proposing a new master should publish the master to the propose queue" do
      host = "my_host"
      port = "my_port"
      payload = {'host' => host, 'port' => port}
      new_master = redis_stub("new_master", payload)
      RedisCoordinator.client.expects(:publish).with do |message_name, json|
        message_name == :propose && ActiveSupport::JSON.decode(json) == payload
      end
      RedisCoordinator.propose(new_master)
    end

    test "propose should create a timer to check for promises" do
      EM.stubs(:add_timer).yields
      RedisCoordinator.expects(:check_propose_answers)
      RedisCoordinator.propose(redis_stub('new_master'))
    end

    test "propose should reset the proposal_answers" do
      assert_equal({}, RedisCoordinator.send(:proposal_answers))
      add_alive_server('server1')
      RedisCoordinator.proposal_answers = {'foo' => 'bar'}
      RedisCoordinator.propose(redis_stub('new_master'))
      assert_equal({'server1' => nil}, RedisCoordinator.send(:proposal_answers))
    end

    test "all_alive_servers_promised? should return false if no alive server promised for the new server" do
      add_alive_server('server1')
      new_master = redis_stub('new_master')
      RedisCoordinator.propose(new_master)
      assert !RedisCoordinator.send(:all_alive_servers_promised?, new_master)
    end

    test "all_alive_servers_promised? should return true if all alive server promised for the new server" do
      add_alive_server('server1')
      add_alive_server('server2')
      new_master = redis_stub('new_master')
      RedisCoordinator.promise({'sender_name' => 'server1', 'acked_server' => new_master.server})
      RedisCoordinator.promise({'sender_name' => 'server2', 'acked_server' => new_master.server})
      assert RedisCoordinator.send(:all_alive_servers_promised?, new_master)
    end


    test "check_propose_answers should setup a new timer if not every server has answered" do
      new_master = redis_stub('new_master')
      EM.expects(:add_timer).twice.yields
      RedisCoordinator.stubs(:reconfigure)
      RedisCoordinator.expects(:all_alive_servers_promised?).twice.returns(false).then.returns(true)
      RedisCoordinator.propose(new_master)
    end

    test "check_propose_answers should stop checking and repropose after xx retries" do
      # flunk <<-GRUEBEL
      # what happens in between?
      # What if a client timed out already?
      # How to keep clients alive in that phase?
      # GRUEBEL
    end

    test "proposing a new master should set the current master to nil" do
      RedisCoordinator.active_master = redis_stub('current master')
      assert RedisCoordinator.active_master
      new_master = redis_stub('new master')
      RedisCoordinator.propose(new_master)
      assert_equal nil, RedisCoordinator.active_master
    end

    test "proposing a new master should give the order to reconfigure if every server accepted the proposal" do
      new_master = redis_stub('new_master')
      EM.stubs(:add_timer).yields
      RedisCoordinator.stubs(:all_alive_servers_promised?).returns(true)
      RedisCoordinator.expects(:reconfigure).with(new_master)
      RedisCoordinator.propose(new_master)
    end

  end

  class RedisCoordinatorReconfigurationTest < Test::Unit::TestCase

    def setup
      stub_watcher_class
      EM.stubs(:add_timer)
    end

    test "the reconfigure method should publish the reconfigure message with the new master data" do
      redis_options = {'host' => 'foobar', 'port' => '1234'}
      new_master    = redis_stub('new_master', redis_options)
      RedisCoordinator.client.expects(:publish).with do |message_name, json|
        message_name == :reconfigure && ActiveSupport::JSON.decode(json) == redis_options
      end
      RedisCoordinator.reconfigure(new_master)
    end

    test "the reconfigure method should start the setup_reconfigured_check_timer" do
      new_master    = redis_stub('new_master')
      RedisCoordinator.expects(:setup_reconfigured_check_timer).with(new_master)
      RedisCoordinator.reconfigure(new_master)
    end

    test "the reconfigure check timer should setup a timer to check wether all workers have answered properly" do
      new_master    = redis_stub('new_master')
      RedisCoordinator.client.config.redis_watcher_propose_timer = 12
      EM.expects(:add_timer).with(12).yields
      RedisCoordinator.expects(:check_reconfigured_answers)
      RedisCoordinator.send(:setup_reconfigured_check_timer, new_master)
    end
    
    test "the all_alive_servers_reconfigured? should return true if all workers have answered properly" do
      flunk      
    end

  end

end

