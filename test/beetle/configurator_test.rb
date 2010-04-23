require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class ConfiguratorTest < Test::Unit::TestCase
    test "process should forward to class methods" do
      message = mock('message', :data => '{"op":"give_master", "somevariable": "somevalue"}')
      configurator = Configurator.new
      configurator.stubs(:message).returns(message)
      Configurator.expects(:give_master).with({"somevariable" => "somevalue"})
      configurator.process()
    end
  end

  class ConfiguratorFindActiveMasterTest < Test::Unit::TestCase

    def setup
      stub_configurator_class
      Configurator.stubs(:setup_propose_check_timer)
    end

    def teardown
      Configurator.alive_servers = {}
    end

    test "find_active_master should return if the current active_master if it is still active set" do
      first_working_redis      = redis_stub('redis1')
      first_working_redis.expects(:info).never
      second_working_redis     = redis_stub('redis2', :info => 'ok')

      Configurator.client.deduplication_store.redis_instances = [first_working_redis, second_working_redis]
      Configurator.active_master = second_working_redis
      Configurator.find_active_master
      assert_equal second_working_redis, Configurator.active_master
    end

    test "find_active_master should retry to reach the current master if it doesn't respond" do
      redis = redis_stub('redis')
      redis.expects(:info).times(2).raises(Timeout::Error).then.returns('ok')
      Beetle.config.redis_watcher_retry_timeout = 0.second
      Beetle.config.redis_watcher_retries       = 1
      Configurator.client.deduplication_store.redis_instances = [redis]
      Configurator.active_master = redis
      Configurator.find_active_master
      assert_equal redis, Configurator.active_master
    end

    test "find_active_master should finally give up to reach the current master after the max timeouts have been reached" do
      non_working_redis  = redis_stub('non-working-redis')
      non_working_redis.expects(:info).raises(Timeout::Error).twice
      working_redis      = redis_stub('working-redis')
      working_redis.expects(:info).returns("ok")

      Beetle.config.redis_watcher_retry_timeout   = 0.second
      Beetle.config.redis_watcher_retries         = 1
      Configurator.client.deduplication_store.redis_instances = [non_working_redis, working_redis]
      Configurator.active_master = non_working_redis
      Configurator.find_active_master
    end

    test "find_active_master should propose the first redis it consideres as working" do
      Configurator.active_master = nil
      working_redis = redis_stub('working-redis', :info => "ok")
      Configurator.client.deduplication_store.redis_instances = [working_redis]
      Configurator.expects(:propose).with(working_redis)
      Configurator.find_active_master
    end

    test "the current master should be set to nil during the proposal phase" do
      Configurator.expects(:clear_active_master)
      Configurator.propose(redis_stub('new_master'))
    end

    test "clear active master should set the current master to nil" do
      Configurator.active_master = "snafu"
      Configurator.send(:clear_active_master)
      assert_nil Configurator.active_master
    end

    test "give master should return the current master" do
      Configurator.active_master = "foobar"
      assert_equal 'foobar', Configurator.give_master({:server_name => 'foo'})
    end

    test "give master should set an alive timestamp for the given server" do
      assert !Configurator.server_alive?('foo')
      Configurator.give_master({'server_name' => 'foo'})
      assert Configurator.server_alive?('foo')
    end

    test "servers that didnt ask for a server within the last 10 seconds are to be marked dead" do
      add_alive_server('bar')
      Configurator.alive_servers['bar'] = Time.now - 10.seconds
      assert !Configurator.server_alive?('bar')
    end
  end

  class ConfiguratorProposingTest < Test::Unit::TestCase

    def setup
      stub_configurator_class
      EM.stubs(:add_timer)
    end

    def teardown
      Configurator.reset
    end

    test "proposing a new master should publish the master to the propose queue" do
      host = "my_host"
      port = "my_port"
      payload = {'host' => host, 'port' => port}
      new_master = redis_stub("new_master", payload)
      Configurator.client.expects(:publish).with do |message_name, json|
        message_name == :propose && ActiveSupport::JSON.decode(json) == payload
      end
      Configurator.propose(new_master)
    end

    test "propose should create a timer to check for promises" do
      EM.stubs(:add_timer).yields
      Configurator.expects(:check_propose_answers)
      Configurator.propose(redis_stub('new_master'))
    end

    test "propose should reset the proposal_answers" do
      assert_equal({}, Configurator.send(:proposal_answers))
      add_alive_server('server1')
      Configurator.proposal_answers = {'foo' => 'bar'}
      Configurator.propose(redis_stub('new_master'))
      assert_equal({'server1' => nil}, Configurator.send(:proposal_answers))
    end

    test "all_alive_servers_promised? should return false if no alive server promised for the new server" do
      add_alive_server('server1')
      new_master = redis_stub('new_master')
      Configurator.propose(new_master)
      assert !Configurator.send(:all_alive_servers_promised?, new_master)
    end

    test "all_alive_servers_promised? should return true if all alive server promised for the new server" do
      add_alive_server('server1')
      add_alive_server('server2')
      new_master = redis_stub('new_master')
      Configurator.promise({'sender_name' => 'server1', 'acked_server' => new_master.server})
      Configurator.promise({'sender_name' => 'server2', 'acked_server' => new_master.server})
      assert Configurator.send(:all_alive_servers_promised?, new_master)
    end


    test "check_propose_answers should setup a new timer if not every server has answered" do
      new_master = redis_stub('new_master')
      EM.expects(:add_timer).twice.yields
      Configurator.stubs(:reconfigure!)
      Configurator.expects(:all_alive_servers_promised?).twice.returns(false).then.returns(true)
      Configurator.propose(new_master)
    end

    test "check_propose_answers should stop checking and repropose after xx retries" do
      # flunk <<-GRUEBEL
      # what happens in between?
      # What if a client timed out already?
      # How to keep clients alive in that phase?
      # GRUEBEL
    end

    test "proposing a new master should set the current master to nil" do
      Configurator.active_master = redis_stub('current master')
      assert Configurator.active_master
      new_master = redis_stub('new master')
      Configurator.propose(new_master)
      assert_equal nil, Configurator.active_master
    end

    test "proposing a new master should give the order to reconfigure if every server accepted the proposal" do
      new_master = redis_stub('new_master')
      EM.stubs(:add_timer).yields
      Configurator.stubs(:all_alive_servers_promised?).returns(true)
      Configurator.expects(:reconfigure!).with(new_master)
      Configurator.propose(new_master)
    end

    test "proposing a new master should wait for the reconfigured message from every known server after giving the order to reconfigure" do
    end

  end

end
