require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class RedisAssumptionsTest < MiniTest::Unit::TestCase
    def setup
      @r = DeduplicationStore.new.redis
      @r.flushdb
    end

    test "trying to delete a non existent key doesn't throw an error" do
      assert !@r.exists("hahahaha")
      assert_equal 0, @r.del("hahahaha")
    end

    test "msetnx returns a boolean" do
      assert_equal true, @r.msetnx("a", 1, "b", 2)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
      assert_equal false, @r.msetnx("a", 3, "b", 4)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
    end
  end

  class RedisServerStringTest < MiniTest::Unit::TestCase
    def setup
      @original_redis_server = Beetle.config.redis_server
      @store = DeduplicationStore.new
      @server_string = "my_test_host_from_file:9999"
      Beetle.config.redis_server = @server_string
    end

    def teardown
      Beetle.config.redis_server = @original_redis_server
    end

    test "redis should match the redis server string" do
      assert_equal @server_string, @store.redis.server
    end
  end

  class RedisServerFileTest < MiniTest::Unit::TestCase
    def setup
      @original_redis_server = Beetle.config.redis_server
      @store = DeduplicationStore.new
      @server_string = "my_test_host_from_file:6379"
      Beetle.config.redis_server = redis_test_master_file(@server_string)
    end

    def teardown
      Beetle.config.redis_server = @original_redis_server
    end

    test "redis should match the redis master file" do
      assert_equal @server_string, @store.redis.server
    end

    test "redis should be nil if the redis master file is blank" do
      redis_test_master_file("")
      assert_nil @store.redis
    end

    test "should keep using the current redis if the redis master file hasn't changed since the last request" do
      @store.expects(:read_master_file).once.returns("localhost:1")
      2.times { @store.redis }
    end

    test "should blow up if the master file doesn't exist" do
      Beetle.config.redis_server = "/tmp/__i_don_not_exist__.txt"
      assert_raises(Errno::ENOENT) { @store.redis_master_from_master_file }
    end

    private
    def redis_test_master_file(server_string)
      tmp_dir = File.expand_path("../../../tmp", __FILE__)
      Dir.mkdir(tmp_dir) unless File.exists?(tmp_dir)
      path = tmp_dir + "/redis-master-for-unit-tests"
      File.open(path, "w"){|f| f.puts server_string}
      path
    end
  end

  class RedisFailoverTest < MiniTest::Unit::TestCase
    def setup
      @store = DeduplicationStore.new
      Beetle.config.expects(:redis_failover_timeout).returns(1)
    end

    test "a redis operation protected with a redis failover block should succeed if it can find a new master" do
      redis1 = stub("redis 1")
      redis2 = stub("redis 2")
      s = sequence("redis accesses")
      @store.expects(:redis).returns(redis1).in_sequence(s)
      redis1.expects(:get).with("foo:x").raises("disconnected").in_sequence(s)
      @store.expects(:redis).returns(redis2).in_sequence(s)
      redis2.expects(:get).with("foo:x").returns("42").in_sequence(s)
      @store.logger.expects(:info)
      @store.logger.expects(:error)
      assert_equal("42", @store.get("foo", "x"))
    end

    test "a redis operation protected with a redis failover block should fail if it cannot find a new master" do
      redis1 = stub()
      @store.stubs(:redis).returns(redis1)
      redis1.stubs(:get).with("foo:x").raises("disconnected")
      @store.stubs(:sleep)
      @store.logger.stubs(:info)
      @store.logger.stubs(:error)
      assert_raises(NoRedisMaster) { @store.get("foo", "x") }
    end
  end

  class GarbageCollectionTest < MiniTest::Unit::TestCase
    def setup
      @store = DeduplicationStore.new
      Beetle.config.stubs(:gc_threshold).returns(10)
    end

    test "never tries to delete message keys when expire key does not exist" do
      key = "foo"
      @store.redis.del key
      @store.redis.expects(:del).never
      assert !@store.gc_key(key, 0)
    end

    test "rescues exeptions and logs an error" do
      RedisServerInfo.expects(:new).raises("foo")
      assert_nothing_raised { @store.garbage_collect_keys_using_master_and_slave }
    end

    test "logs an error when system command fails" do
      @store.stubs(:system).returns(false)
      @store.logger.expects(:error)
      @store.garbage_collect_keys_using_master_and_slave
    end

    test "garbage collects a key when it has expired" do
      key = "foo"
      t = Time.now.to_i
      @store.redis.set(key, t)
      @store.redis.expects(:del)
      assert @store.gc_key(key, t+1)
    end

    test "does not garbage collect a key when it has not expired" do
      key = "foo"
      t = Time.now.to_i
      @store.redis.set(key, t)
      @store.redis.expects(:del).never
      assert !@store.gc_key(key, t)
    end

    test "correctly sets threshold for garbage collection" do
      t = Time.now.to_i
      @store.redis.expects(:keys).returns(["foo"])
      @store.expects(:gc_key).with("foo", t-10)
      @store.garbage_collect_keys
    end

  end
end
