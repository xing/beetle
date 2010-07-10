require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class RedisMasterFileTest < Test::Unit::TestCase
    include Logging
    include RedisMasterFile

    def setup
      File.open(master_file, "w"){|f| f.puts "localhost:6379"}
    end

    def teardown
      File.unlink(master_file) if File.exist?(master_file)
    end

    test "should be able to check existence" do
      assert master_file_exists?
      File.unlink(master_file)
      assert !master_file_exists?
    end

    test "should be able to read and write the master file"do
      write_redis_master_file("localhost:6380")
      assert_equal "localhost:6380", read_redis_master_file
    end

    test "should be able to clear the master file" do
      logger.expects(:warn)
      clear_redis_master_file
      assert_equal "", read_redis_master_file
    end

    private
    def master_file
      "/tmp/mumu.txt"
    end
  end
end
