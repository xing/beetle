require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class EncodingTest < Test::Unit::TestCase
    test "a message should encode/decode the message format version correctly" do
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal Message::FORMAT_VERSION, m.format_version
    end

    test "a redundantly encoded message should have the redundant flag set on delivery" do
      body = Message.encode("12345", :redundant => true)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert m.redundant?
      assert_equal(Message::FLAG_REDUNDANT, m.flags & Message::FLAG_REDUNDANT)
    end

    test "encoding a message with a specfied time to live should set an expiration time" do
      Message.expects(:ttl_to_expiration_time).with(17).returns(42)
      body = Message.encode("12345", :ttl => 17)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 42, m.expires_at
    end

    test "encoding a message should set the default expiration date if none is provided in the call to encode" do
      Message.expects(:ttl_to_expiration_time).with(Message::DEFAULT_TTL).returns(42)
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 42, m.expires_at
    end
  end

  class KeyManagementTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "successful processing of a non redundant message should delete all keys from the database" do
      body = Message.encode('my message', :redundant => false)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert !message.redundant?

      message.process(lambda {|*args|})

      message.all_keys.each do |key|
        assert !@r.exists(key)
      end
    end

    test "succesful processing of a redundant message twice should delete all keys from the database" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack).twice
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert message.redundant?

      message.process(lambda {|*args|})
      message.process(lambda {|*args|})

      message.all_keys.each do |key|
        assert !@r.exists(key)
      end
    end

    test "successful processing of a redundant message once should insert all but the delay key and the exception count key into the database" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert message.redundant?

      message.process(lambda {|*args|})

      assert @r.exists(message.status_key)
      assert @r.exists(message.execution_attempts_key)
      assert @r.exists(message.timeout_key)
      assert @r.exists(message.ack_count_key)
      assert !@r.exists(message.delay_key)
      assert !@r.exists(message.exceptions_key)
    end
  end

  class AckingTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "an expired message should be acked without calling the handler" do
      body = Message.encode('my message', :ttl => -1)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)
      assert message.expired?

      processed = :no
      message.process(lambda {|*args| processed = true})
      assert_equal :no, processed
    end

    test "a delayed message should not be acked and the handler should not be called" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack).never
      message = Message.new("somequeue", header, body)
      message.set_delay!
      assert !message.key_exists?
      assert message.delayed?

      processed = :no
      message.process(lambda {|*args| processed = true})
      assert_equal :no, processed
    end

    test "acking a non redundant message should remove the ack_count key" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      message.process(lambda {|*args|})
      assert !message.redundant?
      assert !@r.exists(message.ack_count_key)
    end

    test "a redundant message should be acked after calling the handler" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)

      message.expects(:ack!)
      assert message.redundant?
      message.process(lambda {|*args|})
    end

    test "acking a redundant message should increment the ack_count key" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert_equal nil, @r.get(message.ack_count_key)
      message.process(lambda {|*args|})
      assert message.redundant?
      assert_equal "1", @r.get(message.ack_count_key)
    end

    test "acking a redundant message twice should remove the ack_count key" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack).twice
      message = Message.new("somequeue", header, body)

      message.process(lambda {|*args|})
      message.process(lambda {|*args|})
      assert message.redundant?
      assert !@r.exists(message.ack_count_key)
    end

  end

  class FreshMessageTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "processing a fresh message sucessfully should first run the handler and then ack it" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.attempts_limit_reached?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      assert_equal Message::RC::OK, message.process(proc)
    end

    test "after processing a redundant fresh message successfully the ack count should be 1 and the status should be completed" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body, :timeout => 10.seconds)
      assert !message.attempts_limit_reached?
      assert message.redundant?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      message.expects(:completed!).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      assert_equal Message::RC::OK, message.__send__(:process_internal, proc)
      assert_equal "1", @r.get(message.ack_count_key)
    end

  end

  class HandlerCrashTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "a message should not be acked if the handler crashes and the exception limit has not been reached" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :delay => 42, :timeout => 10.seconds, :attempts => 2, :exceptions => 2)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?

      proc = lambda {|*args| raise "crash"}
      message.stubs(:now).returns(10)
      message.expects(:completed!).never
      header.expects(:ack).never
      assert_equal Message::RC::HandlerCrash, message.__send__(:process_internal, proc)
      assert !message.completed?
      assert_equal "1", @r.get(message.exceptions_key)
      assert_equal "0", @r.get(message.timeout_key)
      assert_equal "52", @r.get(message.delay_key)
    end

    test "a message should be acked if the handler crashes and the exception limit has been reached" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :timeout => 10.seconds, :attempts => 2, :exceptions => 0)
      assert !message.attempts_limit_reached?
      assert message.exceptions_limit_reached?
      assert !message.timed_out?

      proc = lambda {|*args| raise "crash"}
      s = sequence("s")
      message.expects(:completed!).never
      header.expects(:ack)
      assert_equal Message::RC::ExceptionsLimitReached, message.__send__(:process_internal, proc)
    end

    test "a message should be acked if the handler crashes and the attempts limit has been reached" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :timeout => 10.seconds, :attempts => 1, :exceptions => 1)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?

      proc = lambda {|*args| raise "crash"}
      s = sequence("s")
      message.expects(:completed!).never
      header.expects(:ack)
      assert_equal Message::RC::AttemptsLimitReached, message.__send__(:process_internal, proc)
    end

  end

  class SeenMessageTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "a completed existing message should be just acked and not run the handler" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.key_exists?
      message.completed!
      assert message.completed?

      proc = mock("proc")
      s = sequence("s")
      header.expects(:ack)
      proc.expects(:call).never
      assert_equal Message::RC::OK, message.__send__(:process_internal, proc)
    end

    test "an incomplete, delayed existing message should be processed later" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :delay => 10.seconds)
      assert !message.key_exists?
      assert !message.completed?
      message.set_delay!
      assert message.delayed?

      proc = mock("proc")
      s = sequence("s")
      header.expects(:ack).never
      proc.expects(:call).never
      assert_equal Message::RC::Delayed, message.__send__(:process_internal, proc)
      assert message.delayed?
      assert !message.completed?
    end

    test "an incomplete, undelayed, not yet timed out, existing message should be processed later" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :timeout => 10.seconds)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.set_timeout!
      assert !message.timed_out?

      proc = mock("proc")
      s = sequence("s")
      header.expects(:ack).never
      proc.expects(:call).never
      assert_equal Message::RC::HandlerNotYetTimedOut, message.__send__(:process_internal, proc)
      assert !message.delayed?
      assert !message.completed?
      assert !message.timed_out?
    end

    test "an incomplete, undelayed, not yet timed out, existing message which has reached the handler execution attempts limit should be acked and not run the handler" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?

      assert !message.attempts_limit_reached?
      message.attempts_limit.times {message.increment_execution_attempts!}
      assert message.attempts_limit_reached?

      proc = mock("proc")
      header.expects(:ack)
      proc.expects(:call).never
      assert_equal Message::RC::AttemptsLimitReached, message.send(:process_internal, proc)
    end

    test "an incomplete, undelayed, timed out, existing message which has reached the exceptions limit should be acked and not run the handler" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?
      assert !message.attempts_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?

      proc = mock("proc")
      header.expects(:ack)
      proc.expects(:call).never
      assert_equal Message::RC::ExceptionsLimitReached, message.send(:process_internal, proc)
    end

    test "an incomplete, undelayed, timed out, existing message should be processed again if the mutex can be aquired" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?

      proc = mock("proc")
      s = sequence("s")
      message.expects(:set_timeout!).in_sequence(s)
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      assert_equal Message::RC::OK, message.__send__(:process_internal, proc)
      assert message.completed?
    end

    test "an incomplete, undelayed, timed out, existing message should not be processed again if the mutex cannot be aquired" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      message.aquire_mutex!
      assert @r.exists(message.mutex_key)

      proc = mock("proc")
      proc.expects(:call).never
      header.expects(:ack).never
      assert_equal Message::RC::MutexLocked, message.__send__(:process_internal, proc)
      assert !message.completed?
      assert !@r.exists(message.mutex_key)
    end

  end

  class ProcessingTest < Test::Unit::TestCase
    test "processing a message catches internal exceptions risen by process_internal and returns an internal error" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.expects(:process_internal).raises(Exception.new)
      handler = Handler.new
      handler.expects(:process_exception).never
      handler.expects(:process_failure).never
      assert_equal Message::RC::InternalError, message.process(1)
    end

    test "processing a message with a crashing processor calls the processors exception handler and returns an internal error" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :attempts => 2, :exceptions => 2)
      errback = lambda{|*args|}
      exception = Exception.new
      action = lambda{|*args| raise exception}
      handler = Handler.create(action, :errback => errback)
      handler.expects(:process_exception).with(exception).once
      handler.expects(:process_failure).never
      result = message.process(handler)
      assert_equal Message::RC::HandlerCrash, result
      assert result.recover?
      assert !result.failure?
    end

    test "processing a message with a crashing processor and attempts limit 1 calls the processors exception handler and the failure handler" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)
      errback = mock("errback")
      failback = mock("failback")
      exception = Exception.new
      action = lambda{|*args| raise exception}
      handler = Handler.create(action, :errback => errback, :failback => failback)
      errback.expects(:call).once
      failback.expects(:call).once
      result = message.process(handler)
      assert_equal Message::RC::AttemptsLimitReached, result
      assert !result.recover?
      assert result.failure?
    end

    test "processing a message with a crashing processor and exceptions limit 1 calls the processors exception handler and the failure handler" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body, :attempts => 2)
      errback = mock("errback")
      failback = mock("failback")
      exception = Exception.new
      action = lambda{|*args| raise exception}
      handler = Handler.create(action, :errback => errback, :failback => failback)
      errback.expects(:call).once
      failback.expects(:call).once
      result = message.process(handler)
      assert_equal Message::RC::ExceptionsLimitReached, result
      assert !result.recover?
      assert result.failure?
    end

  end

  class SettingsTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "completed! should store the status 'complete' in the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.completed?
      message.completed!
      assert message.completed?
      assert_equal "completed", @r.get(message.status_key)
    end

    test "set_delay! should store the current time plus the number of delayed seconds in the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :delay => 1)
      message.expects(:now).returns(1)
      message.set_delay!
      assert_equal "2", @r.get(message.delay_key)
      message.expects(:now).returns(2)
      assert !message.delayed?
      message.expects(:now).returns(0)
      assert message.delayed?
    end

    test "set_delay! should use the default delay if the delay hasn't been set on the message instance" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.expects(:now).returns(0)
      message.set_delay!
      assert_equal "#{Message::DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY}", @r.get(message.delay_key)
      message.expects(:now).returns(message.delay)
      assert !message.delayed?
      message.expects(:now).returns(0)
      assert message.delayed?
    end

    test "set_timeout! should store the current time plus the number of timeout seconds in the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :timeout => 1)
      message.expects(:now).returns(1)
      message.set_timeout!
      assert_equal "2", @r.get(message.timeout_key)
      message.expects(:now).returns(2)
      assert !message.timed_out?
      message.expects(:now).returns(3)
      assert message.timed_out?
    end

    test "set_timeout! should use the default timeout if the timeout hasn't been set on the message instance" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.expects(:now).returns(0)
      message.set_timeout!
      assert_equal "#{Message::DEFAULT_HANDLER_TIMEOUT}", @r.get(message.timeout_key)
      message.expects(:now).returns(message.timeout)
      assert !message.timed_out?
      message.expects(:now).returns(Message::DEFAULT_HANDLER_TIMEOUT+1)
      assert message.timed_out?
    end

    test "incrementing execution attempts should increment by 1" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert_equal 1, message.increment_execution_attempts!
      assert_equal 2, message.increment_execution_attempts!
      assert_equal 3, message.increment_execution_attempts!
    end

    test "attempts limit should be reached after incrementing the attempt limit counter 'attempts limit' times" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :attempts =>2)
      assert !message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert !message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert message.attempts_limit_reached?
    end

    test "incrementing exception counts should increment by 1" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert_equal 1, message.increment_exception_count!
      assert_equal 2, message.increment_exception_count!
      assert_equal 3, message.increment_exception_count!
    end

    test "exceptions limit should be reached after incrementing the attempt limit counter 'exceptions limit' times" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :exceptions => 2)
      assert !message.exceptions_limit_reached?
      message.increment_exception_count!
      assert !message.exceptions_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?
    end

    test "failure to aquire a mutex should delete it from the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert message.aquire_mutex!
      assert !message.aquire_mutex!
      assert !@r.exists(message.mutex_key)
    end
  end

  class RedisAssumptionsTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "trying to delete a non existent key doesn't throw an error" do
      assert !@r.del("hahahaha")
      assert !@r.exists("hahahaha")
    end
  end
end

