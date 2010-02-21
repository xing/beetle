require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class EncodingTest < Test::Unit::TestCase
    test "a message should encode/decode the message format version correctly" do
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal Message::FORMAT_VERSION, m.format_version
    end

    test "a message should encode/decode the version 1 message format correctly" do
      body = Message.encode1("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 1, m.format_version
    end

    test "a redundantly encoded message should have the redundant flag set on delivery" do
      body = Message.encode("12345", :redundant => true)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert m.redundant?
      assert_equal(Message::FLAG_REDUNDANT, m.flags & Message::FLAG_REDUNDANT)
    end

    test "a version format 1 redundantly encoded message should have the redundant flag set on delivery" do
      body = Message.encode1("12345", :redundant => true)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert m.redundant?
      assert_equal(Message::FLAG_REDUNDANT, m.flags & Message::FLAG_REDUNDANT)
    end

    test "encoding a message with a specfied time to live should set an expiration time" do
      Message.expects(:now).returns(25)
      body = Message.encode("12345", :ttl => 17)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 42, m.expires_at
    end

    test "encoding a format 1 message with a specfied time to live should set an expiration time" do
      Message.expects(:now).returns(25)
      body = Message.encode1("12345", :ttl => 17)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 42, m.expires_at
    end

    test "encoding a message should set the default expiration date if none is provided in the call to encode" do
      Message.expects(:now).returns(1)
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 1+Message::DEFAULT_TTL, m.expires_at
    end

    test "encoding a format 1 message should set the default expiration date if none is provided in the call to encode" do
      Message.expects(:now).returns(1)
      body = Message.encode1("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 1+Message::DEFAULT_TTL, m.expires_at
    end

    test "encoding a message with a specfied start time should set the start time attribute" do
      Message.expects(:now).returns(25)
      body = Message.encode("12345", :delay => 17)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 42, m.starts_at
    end

    test "encoding a message without a specfied start time should set the start time attribute to the encoding time" do
      Message.expects(:now).returns(25)
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 25, m.starts_at
    end
  end

  class KeyManagementTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "should be able to extract msg_id from any key" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.keys.each do |key|
        assert_equal message.msg_id, Message.msg_id(key)
      end
    end

    test "should be able to garbage collect expired keys" do
      Beetle.config.expects(:gc_threshold).returns(0)
      body = Message.encode('my message', :ttl => 0)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.key_exists?
      assert message.key_exists?
      Message.stubs(:now).returns(Time.now.to_i+1)
      @r.expects(:del).with(message.keys)
      Message.garbage_collect_keys
    end

    test "should not garbage collect not yet expired keys" do
      Beetle.config.expects(:gc_threshold).returns(0)
      body = Message.encode('my message', :ttl => 0)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.key_exists?
      assert message.key_exists?
      Message.stubs(:now).returns(Time.now.to_i-1)
      @r.expects(:del).never
      Message.garbage_collect_keys
    end

    test "successful processing of a non redundant message should delete all keys from the database" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert !message.redundant?

      message.process(lambda {|*args|})

      message.keys.each do |key|
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

      message.keys.each do |key|
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

      assert @r.exists(message.key :status)
      assert @r.exists(message.key :expires)
      assert @r.exists(message.key :attempts)
      assert @r.exists(message.key :timeout)
      assert @r.exists(message.key :ack_count)
      assert !@r.exists(message.key :delay)
      assert !@r.exists(message.key :exceptions)
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
      assert !@r.exists(message.key :ack_count)
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

      assert_equal nil, @r.get(message.key :ack_count)
      message.process(lambda {|*args|})
      assert message.redundant?
      assert_equal "1", @r.get(message.key :ack_count)
    end

    test "acking a redundant message twice should remove the ack_count key" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack).twice
      message = Message.new("somequeue", header, body)

      message.process(lambda {|*args|})
      message.process(lambda {|*args|})
      assert message.redundant?
      assert !@r.exists(message.key :ack_count)
    end
  end

  class NotYetStartedMessageTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "processing a message which a starts_at date in the future should not run the handler, it should not be acked and should not insert any keys into the database" do
      body = Message.encode('my message', :delay => 2)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.started?

      proc = mock("proc")
      proc.expects(:call).never
      header.expects(:ack).never
      assert_equal RC::Delayed, message.process(proc)
      message.keys.each do |key|
        assert !@r.exists(key)
      end
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
      assert_equal RC::OK, message.process(proc)
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
      assert_equal RC::OK, message.__send__(:process_internal, proc)
      assert_equal "1", @r.get(message.key :ack_count)
    end
  end

  class HandlerCrashTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "a message should not be acked if the handler crashes and the exception limit has not been reached" do
      Message.stubs(:now).returns(9)
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :delay => 42, :timeout => 10.seconds, :attempts => 2, :exceptions => 2)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?
      assert message.started?

      proc = lambda {|*args| raise "crash"}
      message.stubs(:now).returns(10)
      message.expects(:completed!).never
      header.expects(:ack).never
      assert_equal RC::HandlerCrash, message.__send__(:process_internal, proc)
      assert !message.completed?
      assert_equal "1", @r.get(message.key :exceptions)
      assert_equal "0", @r.get(message.key :timeout)
      assert_equal "52", @r.get(message.key :delay)
    end

    test "a message should be acked if the handler crashes and the exception limit has been reached" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :timeout => 10.seconds, :attempts => 2, :exceptions => 0)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?

      proc = lambda {|*args| raise "crash"}
      s = sequence("s")
      message.expects(:completed!).never
      header.expects(:ack)
      assert_equal RC::ExceptionsLimitReached, message.__send__(:process_internal, proc)
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
      assert_equal RC::AttemptsLimitReached, message.__send__(:process_internal, proc)
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
      assert_equal RC::OK, message.__send__(:process_internal, proc)
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
      assert_equal RC::Delayed, message.__send__(:process_internal, proc)
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
      assert_equal RC::HandlerNotYetTimedOut, message.__send__(:process_internal, proc)
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
      assert_equal RC::AttemptsLimitReached, message.send(:process_internal, proc)
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
      assert_equal RC::ExceptionsLimitReached, message.send(:process_internal, proc)
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
      assert_equal RC::OK, message.__send__(:process_internal, proc)
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
      assert @r.exists(message.key :mutex)

      proc = mock("proc")
      proc.expects(:call).never
      header.expects(:ack).never
      assert_equal RC::MutexLocked, message.__send__(:process_internal, proc)
      assert !message.completed?
      assert !@r.exists(message.key :mutex)
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
      assert_equal RC::InternalError, message.process(1)
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
      assert_equal RC::HandlerCrash, result
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
      assert_equal RC::AttemptsLimitReached, result
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
      assert_equal RC::ExceptionsLimitReached, result
      assert !result.recover?
      assert result.failure?
    end
  end

  class HandlerTimeoutTest < Test::Unit::TestCase
    test "a handler running longer than the specified timeout should be aborted" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body, :timeout => 0.1)
      action = lambda{|*args| while true; end}
      handler = Handler.create(action)
      result = message.process(handler)
      assert_equal RC::AttemptsLimitReached, result
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
      assert_equal "completed", @r.get(message.key :status)
    end

    test "set_delay! should store the current time plus the number of delayed seconds in the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :delay => 1)
      message.expects(:now).returns(1)
      message.set_delay!
      assert_equal "2", @r.get(message.key :delay)
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
      assert_equal "#{Message::DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY}", @r.get(message.key :delay)
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
      assert_equal "2", @r.get(message.key :timeout)
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
      assert_equal "#{Message::DEFAULT_HANDLER_TIMEOUT}", @r.get(message.key :timeout)
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

    test "accessing execution attempts should return the number of execution attempts made so far" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert_equal 0, message.attempts
      message.increment_execution_attempts!
      assert_equal 1, message.attempts
      message.increment_execution_attempts!
      assert_equal 2, message.attempts
      message.increment_execution_attempts!
      assert_equal 3, message.attempts
    end

    test "accessing execution attempts should return 0 if none were made" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert_equal 0, message.attempts
    end


    test "attempts limit should be set exception limit + 1 iff the configured attempts limit is smaller than the exceptions limit" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :exceptions => 2)
      assert_equal 3, message.attempts_limit
      assert_equal 2, message.exceptions_limit
      message = Message.new("somequeue", header, body, :attempts => 5, :exceptions => 2)
      assert_equal 5, message.attempts_limit
      assert_equal 2, message.exceptions_limit
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

    test "default exceptions limit should be reached after incrementing the attempt limit counter 1 time" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.exceptions_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?
    end

    test "exceptions limit should be reached after incrementing the attempt limit counter 'exceptions limit + 1' times" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body, :exceptions => 1)
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
      assert !@r.exists(message.key :mutex)
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

    test "msetnx returns an 0 or 1" do
      assert_equal 1, @r.msetnx("a" => 1, "b" => 2)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
      assert_equal 0, @r.msetnx("a" => 3, "b" => 4)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
    end
  end
end

