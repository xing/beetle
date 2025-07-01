require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  module BunnySessionTest
    class BunnyInternalAPITest < Minitest::Test
      test "internal methods exist on Bunny::Session" do
        session = Bunny::Session.new

        assert session.protected_methods.include?(:maybe_shutdown_heartbeat_sender), "Bunny::Session should have maybe_shutdown_heartbeat_sender"
        assert session.protected_methods.include?(:maybe_close_transport), "Bunny::Session should have maybe_close_transport"

        assert_respond_to session, :reader_loop, "Bunny::Session should have reader_loop"
        assert_respond_to session, :close_connection, "Bunny::Session should have close_connection"
      end
    end

    class SmokeTests < Minitest::Test
      test "smoke test" do
        session = Beetle::BunnySession.new(host: "localhost", port: 5672)

        assert_nothing_raised do
          session.start_safely
        end

        assert session._reader_loop_alive?, "Reader loop should be alive after start_safely"
        assert session._heartbeat_sender_alive?, "Heartbeat sender should be alive after start_safely"

        assert_nothing_raised do
          session.stop_safely
        end

        assert session.closed?, "Session should be closed after stop_safely"
        refute session._reader_loop_alive?, "Reader loop should not be alive after stop_safely"
        refute session._heartbeat_sender_alive?, "Heartbeat sender should not be alive after stop_safely"
        assert session.transport.closed?, "Transport should be closed after stop_safely"
      end

      test "smoke test partial failure" do
        session = Beetle::BunnySession.new(host: "localhost", port: 5672)

        assert_nothing_raised do
          session.start_safely
        end

        session.expects(:maybe_shutdown_heartbeat_sender).raises(StandardError, "Simulated connection error").at_least_once

        assert_raises(Beetle::BunnySession::ShutdownError) do
          session.stop_safely
        end

        refute session._reader_loop_alive?, "Reader loop should not be alive after stop_safely"
        assert session.transport.closed?, "Transport should be closed after stop_safely"
      end
    end

    class SafeShutdownTest < Minitest::Test
      def assert_bunny_shutdown_sequence_with_error(session, fail_on)
        reader_loop = mock

        session.expects(:reader_loop).at_least_once.returns(reader_loop)

        if fail_on == :heartbeat_sender
          session.expects(:maybe_shutdown_heartbeat_sender).raises(StandardError, "Simulated heartbeat sender error").at_least_once
        else
          session.expects(:maybe_shutdown_heartbeat_sender).at_least_once
        end

        if fail_on == :connection
          session.expects(:close_connection).with(false).raises(StandardError, "Simulated connection close error").at_least_once
        else
          session.expects(:close_connection).with(false).at_least_once
        end

        if fail_on == :transport
          session.expects(:maybe_close_transport).raises(StandardError, "Simulated transport close error").at_least_once
        else
          session.expects(:maybe_close_transport).at_least_once
        end

        if fail_on == :reader_loop
          reader_loop.expects(:kill).raises(StandardError, "Simulated reader loop kill error").at_least_once
        else
          reader_loop.expects(:kill).at_least_once
        end
      end

      test "stops the background threads and the connection" do
        reader_loop = mock

        session = Beetle::BunnySession.new
        session.expects(:maybe_shutdown_heartbeat_sender).at_least_once
        session.expects(:reader_loop).at_least_once.returns(reader_loop)
        session.expects(:close_connection).with(false).at_least_once
        session.expects(:maybe_close_transport).at_least_once
        reader_loop.expects(:kill).at_least_once

        session.stop_safely
      end

      test "fails on heartbeat sender but continues shutdown" do
        session = Beetle::BunnySession.new
        assert_bunny_shutdown_sequence_with_error(session, :heartbeat_sender)

        assert_raises(Beetle::BunnySession::ShutdownError) do
          session.stop_safely
        end
      end

      test "fails on reader loop kill but continues shutdown" do
        session = Beetle::BunnySession.new
        assert_bunny_shutdown_sequence_with_error(session, :reader_loop)

        assert_raises(Beetle::BunnySession::ShutdownError) do
          session.stop_safely
        end
      end

      test "fails on connection close but continues shutdown" do
        session = Beetle::BunnySession.new
        assert_bunny_shutdown_sequence_with_error(session, :connection)

        assert_raises(Beetle::BunnySession::ShutdownError) do
          session.stop_safely
        end
      end

      test "fails on transport close but continues shutdown" do
        session = Beetle::BunnySession.new
        assert_bunny_shutdown_sequence_with_error(session, :transport)

        assert_raises(Beetle::BunnySession::ShutdownError) do
          session.stop_safely
        end
      end
    end

    class SafeStartTest < Minitest::Test
    end
  end
end
