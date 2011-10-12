require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class RedisAssumptionsTest < Test::Unit::TestCase
    def setup
      @r = DeduplicationStore.new.redis
      @r.flushdb
    end

    test "trying to delete a non existent key doesn't throw an error" do
      assert !@r.exists("hahahaha")
      assert_equal 0, @r.del("hahahaha")
    end

    test "msetnx returns 0 or 1" do
      assert_equal 1, @r.msetnx("a", 1, "b", 2)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
      assert_equal 0, @r.msetnx("a", 3, "b", 4)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
    end
  end

  class RedisServerStringTest < Test::Unit::TestCase
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

  class RedisServerFileTest < Test::Unit::TestCase
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

    test "should return nil if the master file doesn't exist" do
      Beetle.config.redis_server = "/tmp/__i_don_not_exist__.txt"
      assert_equal nil, @store.redis_master_from_master_file
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

  class RedisFailoverTest < Test::Unit::TestCase
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

end
