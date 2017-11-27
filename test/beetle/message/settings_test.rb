require File.expand_path(File.dirname(__FILE__) + '/../../test_helper')

module Beetle
  class SettingsTest < Minitest::Test
    def setup
      @store = DeduplicationStore.new
      @store.flushdb
    end

    test "completed! should store the status 'complete' in the database" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      assert !message.completed?
      message.completed!
      assert message.completed?
      assert_equal "completed", @store.get(message.msg_id, :status)
    end

    test "set_delay! should store the current time plus the delay offset in the database" do
      message = Message.new("somequeue", header_with_params, 'foo', :delay => 2, :store => @store)
      message.expects(:now).returns(9)
      message.set_delay!
      assert_equal "11", @store.get(message.msg_id, :delay)
      message.expects(:now).returns(12)
      assert !message.delayed?
      message.expects(:now).returns(10)
      assert message.delayed?
    end

    test "set_delay! should store the current time plus the exponential delay offset in the database" do
      message = Message.new("somequeue", header_with_params, 'foo', :delay => 3, :exponential_back_off => 30, :store => @store)
      message.stubs(:now).returns(1)

      [4, 7, 13, 25].each do |exp_delay|
        message.set_delay!
        assert_equal exp_delay, @store.get(message.msg_id, :delay).to_i
        message.increment_execution_attempts!
      end
    end

    test "set_delay! should store the current time plus the exponential delay offset in the database up to given max value" do
      message = Message.new("somequeue", header_with_params, 'foo', :delay => 3, :exponential_back_off => 10, :store => @store)
      message.stubs(:now).returns(1)

      [4, 7, 11, 11].each do |exp_delay|
        message.set_delay!
        assert_equal exp_delay, @store.get(message.msg_id, :delay).to_i
        message.increment_execution_attempts!
      end
    end

    test "set_delay! should store the current time plus the linear delay offset in the database" do
      delay = 32
      message = Message.new("somequeue", header_with_params, 'foo', :delay => delay, :exponential_back_off => nil, :store => @store)
      [3, 5, 6].each do |now_offset|
        message.stubs(:now).returns(now_offset)
        message.set_delay!
        assert_equal @store.get(message.msg_id, :delay).to_i, now_offset + delay
        message.increment_execution_attempts!
      end
    end

    test "set_delay! should use the default delay if the delay hasn't been set on the message instance" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      message.expects(:now).returns(0)
      message.set_delay!
      assert_equal "#{Message::DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY}", @store.get(message.msg_id, :delay)
      message.expects(:now).returns(message.delay)
      assert !message.delayed?
      message.expects(:now).returns(0)
      assert message.delayed?
    end

    test "set_timeout! should store the current time plus the number of timeout seconds in the database" do
      message = Message.new("somequeue", header_with_params, 'foo', :timeout => 1, :store => @store)
      message.expects(:now).returns(1)
      message.set_timeout!
      assert_equal "2", @store.get(message.msg_id, :timeout)
      message.expects(:now).returns(2)
      assert !message.timed_out?
      message.expects(:now).returns(3)
      assert message.timed_out?
    end

    test "set_timeout! should use the default timeout if the timeout hasn't been set on the message instance" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      message.expects(:now).returns(0)
      message.set_timeout!
      assert_equal "#{Message::DEFAULT_HANDLER_TIMEOUT}", @store.get(message.msg_id, :timeout)
      message.expects(:now).returns(message.timeout)
      assert !message.timed_out?
      message.expects(:now).returns(Message::DEFAULT_HANDLER_TIMEOUT + 1)
      assert message.timed_out?
    end

    test "incrementing execution attempts should increment by 1" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      assert_equal 1, message.increment_execution_attempts!
      assert_equal 2, message.increment_execution_attempts!
      assert_equal 3, message.increment_execution_attempts!
    end

    test "accessing execution attempts should return the number of execution attempts made so far" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      assert_equal 0, message.attempts
      message.increment_execution_attempts!
      assert_equal 1, message.attempts
      message.increment_execution_attempts!
      assert_equal 2, message.attempts
      message.increment_execution_attempts!
      assert_equal 3, message.attempts
    end

    test "accessing execution attempts should return 0 if none were made" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      assert_equal 0, message.attempts
    end


    test "attempts limit should be set exception limit + 1 iff the configured attempts limit is equal to or smaller than the exceptions limit" do
      message = Message.new("somequeue", header_with_params, 'foo', :exceptions => 1, :store => @store)
      assert_equal 2, message.attempts_limit
      assert_equal 1, message.exceptions_limit
      message = Message.new("somequeue", header_with_params, 'foo', :exceptions => 2, :store => @store)
      assert_equal 3, message.attempts_limit
      assert_equal 2, message.exceptions_limit
      message = Message.new("somequeue", header_with_params, 'foo', :attempts => 5, :exceptions => 2, :store => @store)
      assert_equal 5, message.attempts_limit
      assert_equal 2, message.exceptions_limit
    end

    test "attempts limit should be reached after incrementing the attempt limit counter 'attempts limit' times" do
      message = Message.new("somequeue", header_with_params, 'foo', :attempts =>2, :store => @store)
      assert !message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert !message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert message.attempts_limit_reached?
    end

    test "incrementing exception counts should increment by 1" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      assert_equal 1, message.increment_exception_count!
      assert_equal 2, message.increment_exception_count!
      assert_equal 3, message.increment_exception_count!
    end

    test "default exceptions limit should be reached after incrementing the attempt limit counter 1 time" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      assert !message.exceptions_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?
    end

    test "exceptions limit should be reached after incrementing the attempt limit counter 'exceptions limit + 1' times" do
      message = Message.new("somequeue", header_with_params, 'foo', :exceptions => 1, :store => @store)
      assert !message.exceptions_limit_reached?
      message.increment_exception_count!
      assert !message.exceptions_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?
    end

    test "failure to aquire a mutex should delete it from the database" do
      message = Message.new("somequeue", header_with_params, 'foo', :store => @store)
      assert message.aquire_mutex!
      assert !message.aquire_mutex!
      assert !@store.exists(message.msg_id, :mutex)
    end
  end
end
