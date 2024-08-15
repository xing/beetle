require 'daemons/pidfile'
require 'daemons/pidmem'
require 'daemons/change_privilege'
require 'daemons/daemonize'
require 'daemons/exceptions'
require 'daemons/reporter'

require 'timeout'

module Daemons
  class Application
    attr_accessor :app_argv
    attr_accessor :controller_argv

    # the Pid instance belonging to this application
    attr_reader :pid

    # the ApplicationGroup the application belongs to
    attr_reader :group

    # my private options
    attr_reader :options

    SIGNAL = (RUBY_PLATFORM =~ /win32/ ? 'KILL' : 'TERM')

    def initialize(group, add_options = {}, pid = nil)
      @group = group
      @options = group.options.dup
      @options.update(add_options)

      ['dir', 'log_dir', 'logfilename', 'output_logfilename'].each do |k|
        @options[k] = File.expand_path(@options[k]) if @options.key?(k)
      end

      @dir_mode = @dir = @script = nil

      @force_kill_waittime = @options[:force_kill_waittime] || 20

      @signals_and_waits = parse_signals_and_waits(@options[:signals_and_waits])

      @show_status_callback = method(:default_show_status)

      @report = Reporter.new(@options)

      unless @pid = pid
        if @options[:no_pidfiles]
          @pid = PidMem.new
        elsif dir = pidfile_dir
          @pid = PidFile.new(dir, @group.app_name, @group.multiple, @options[:pid_delimiter])
        else
          @pid = PidMem.new
        end
      end
    end

    def show_status_callback=(function)
      @show_status_callback =
        if function.respond_to?(:call)
          function
        else
          method(function)
        end
    end

    def change_privilege
      user = options[:user]
      group = options[:group]
      if user
        @report.changing_process_privilege(user, group)
        CurrentProcess.change_privilege(user, group)
      end
    end

    def script
      @script or group.script
    end

    def pidfile_dir
      Pid.dir dir_mode, dir, script
    end

    def logdir
      options[:log_dir] or
        options[:dir_mode] == :system ? '/var/log' : pidfile_dir
    end

    def output_logfilename
      options[:output_logfilename] or "#{@group.app_name}.output"
    end

    def output_logfile
      if log_output_syslog?
        'SYSLOG'
      elsif log_output?
        File.join logdir, output_logfilename
      end
    end

    def logfilename
      options[:logfilename] or "#{@group.app_name}.log"
    end

    def logfile
      if logdir
        File.join logdir, logfilename
      end
    end

    # this function is only used to daemonize the currently running process (Daemons.daemonize)
    def start_none
      unless options[:ontop]
        Daemonize.daemonize(output_logfile, @group.app_name)
      else
        Daemonize.simulate(output_logfile)
      end

      @pid.pid = Process.pid

      # We need this to remove the pid-file if the applications exits by itself.
      # Note that <tt>at_text</tt> will only be run if the applications exits by calling
      # <tt>exit</tt>, and not if it calls <tt>exit!</tt> (so please don't call <tt>exit!</tt>
      # in your application!
      #
      at_exit do
        begin; @pid.cleanup; rescue ::Exception; end

        # If the option <tt>:backtrace</tt> is used and the application did exit by itself
        # create a exception log.
        if options[:backtrace] && !options[:ontop] && !$daemons_sigterm
          begin; exception_log; rescue ::Exception; end
        end

      end

      # This part is needed to remove the pid-file if the application is killed by
      # daemons or manually by the user.
      # Note that the applications is not supposed to overwrite the signal handler for
      # 'TERM'.
      #
      trap(SIGNAL) do
        begin; @pid.cleanup; rescue ::Exception; end
        $daemons_sigterm = true

        if options[:hard_exit]
          exit!
        else
          exit
        end
      end
    end

    def start_exec
      if options[:backtrace]
        @report.backtrace_not_supported
      end

      unless options[:ontop]
        Daemonize.daemonize(output_logfile, @group.app_name)
      else
        Daemonize.simulate(output_logfile)
      end

      # note that we cannot remove the pid file if we run in :ontop mode (i.e. 'ruby ctrl_exec.rb run')
      @pid.pid = Process.pid

      ENV['DAEMONS_ARGV'] = @controller_argv.join(' ')

      started
      Kernel.exec(script, *(@app_argv || []))
    end

    def start_load
      unless options[:ontop]
        Daemonize.daemonize(output_logfile, @group.app_name)
      else
        Daemonize.simulate(output_logfile)
      end

      @pid.pid = Process.pid

      # We need this to remove the pid-file if the applications exits by itself.
      # Note that <tt>at_exit</tt> will only be run if the applications exits by calling
      # <tt>exit</tt>, and not if it calls <tt>exit!</tt> (so please don't call <tt>exit!</tt>
      # in your application!
      #
      at_exit do
        begin; @pid.cleanup; rescue ::Exception; end

        # If the option <tt>:backtrace</tt> is used and the application did exit by itself
        # create a exception log.
        if options[:backtrace] && !options[:ontop] && !$daemons_sigterm
          begin; exception_log; rescue ::Exception; end
        end

      end

      # This part is needed to remove the pid-file if the application is killed by
      # daemons or manually by the user.
      # Note that the applications is not supposed to overwrite the signal handler for
      # 'TERM'.
      #
      $daemons_stop_proc = options[:stop_proc]
      trap(SIGNAL) do
        begin
          if $daemons_stop_proc
            $daemons_stop_proc.call
          end
        rescue ::Exception
        end

        begin; @pid.cleanup; rescue ::Exception; end
        $daemons_sigterm = true

        if options[:hard_exit]
          exit!
        else
          exit
        end
      end

      # Now we really start the script...
      $DAEMONS_ARGV = @controller_argv
      ENV['DAEMONS_ARGV'] = @controller_argv.join(' ')

      ARGV.clear
      ARGV.concat @app_argv if @app_argv

      started
      # TODO: exception logging
      load script
    end

    def start_proc
      return unless p = options[:proc]

      myproc = proc do

        # We need this to remove the pid-file if the applications exits by itself.
        # Note that <tt>at_text</tt> will only be run if the applications exits by calling
        # <tt>exit</tt>, and not if it calls <tt>exit!</tt> (so please don't call <tt>exit!</tt>
        # in your application!
        #
        at_exit do
          begin; @pid.cleanup; rescue ::Exception; end

          # If the option <tt>:backtrace</tt> is used and the application did exit by itself
          # create a exception log.
          if options[:backtrace] && !options[:ontop] && !$daemons_sigterm
            begin; exception_log; rescue ::Exception; end
          end

        end

        # This part is needed to remove the pid-file if the application is killed by
        # daemons or manually by the user.
        # Note that the applications is not supposed to overwrite the signal handler for
        # 'TERM'.
        #
        $daemons_stop_proc = options[:stop_proc]
        trap(SIGNAL) do
          begin
            if $daemons_stop_proc
              $daemons_stop_proc.call
            end
          rescue ::Exception
          end

          begin; @pid.cleanup; rescue ::Exception; end
          $daemons_sigterm = true

          if options[:hard_exit]
            exit!
          else
            exit
          end
        end
        p.call
      end

      unless options[:ontop]
        @pid.pid = Daemonize.call_as_daemon(myproc, output_logfile, @group.app_name)

      else
        Daemonize.simulate(output_logfile)

        myproc.call
      end
      started
    end

    def start(restart = false)
      change_privilege

      unless restart
        @group.create_monitor(self) unless options[:ontop]  # we don't monitor applications in the foreground
      end

      case options[:mode]
        when :none
          # this is only used to daemonize the currently running process
          start_none
        when :exec
          start_exec
        when :load
          start_load
        when :proc
          start_proc
        else
          start_load
      end
    end

    def started
      if pid = @pid.pid
        @report.process_started(group.app_name, pid)
      end
    end

    def reload
      if @pid.pid == 0
        zap
        start
      else
        begin
          Process.kill('HUP', @pid.pid)
        rescue
          # ignore
        end
      end
    end

    # This is a nice little function for debugging purposes:
    # In case a multi-threaded ruby script exits due to an uncaught exception
    # it may be difficult to find out where the exception came from because
    # one cannot catch exceptions that are thrown in threads other than the main
    # thread.
    #
    # This function searches for all exceptions in memory and outputs them to $stderr
    # (if it is connected) and to a log file in the pid-file directory.
    #
    def exception_log
      return unless logfile

      require 'logger'

      l_file = Logger.new(logfile)

      # the code below finds the last exception
      e = nil

      ObjectSpace.each_object do |o|
        if ::Exception === o
          e = o
        end
      end

      l_file.info '*** below you find the most recent exception thrown, this will be likely (but not certainly) the exception that made the application exit abnormally ***'
      l_file.error e

      l_file.info '*** below you find all exception objects found in memory, some of them may have been thrown in your application, others may just be in memory because they are standard exceptions ***'

      # this code logs every exception found in memory
      ObjectSpace.each_object do |o|
        if ::Exception === o
          l_file.error o
        end
      end

      l_file.close
    end

    def stop(no_wait = false)
      unless running?
        zap
        return
      end

      # confusing: pid is also a attribute_reader
      pid = @pid.pid

      # Catch errors when trying to kill a process that doesn't
      # exist. This happens when the process quits and hasn't been
      # restarted by the monitor yet. By catching the error, we allow the
      # pid file clean-up to occur.
      begin
        wait_and_retry_kill_harder(pid, @signals_and_waits, no_wait)
      rescue Errno::ESRCH => e
        @report.output_message("#{e} #{pid}")
        @report.output_message('deleting pid-file.')
      end

      sleep(0.1)
      unless Pid.running?(pid)
        # We try to remove the pid-files by ourselves, in case the application
        # didn't clean it up.
        zap!

        @report.stopped_process(group.app_name, pid)
      end
    end

    # @param Hash remaing_signals
    # @param Boolean no_wait Send first Signal and return
    def wait_and_retry_kill_harder(pid, remaining_signals, no_wait = false)
      sig_wait = remaining_signals.shift
      sig      = sig_wait[:sig]
      wait     = sig_wait[:wait]
      Process.kill(sig, pid)
      return if no_wait || !wait.positive?

      @report.stopping_process(group.app_name, pid, sig, wait)

      begin
        Timeout.timeout(wait, TimeoutError) do
          sleep(0.2) while Pid.running?(pid)
        end
      rescue TimeoutError
        if remaining_signals.any?
          wait_and_retry_kill_harder(pid, remaining_signals)
        else
          @report.cannot_stop_process(group.app_name, pid)
        end
      end
    end

    def zap
      @pid.zap
    end

    def zap!
      begin; @pid.zap; rescue ::Exception; end
    end

    def show_status
      @show_status_callback.call(self)
    end

    def default_show_status(daemon = self)
      running = daemon.running?

      @report.status(group.app_name, running, daemon.pid.exist?, daemon.pid.pid.to_s)
    end

    # This function implements a (probably too simle) method to detect
    # whether the program with the pid found in the pid-file is still running.
    # It just searches for the pid in the output of <tt>ps ax</tt>, which
    # is probably not a good idea in some cases.
    # Alternatives would be to use a direct access method the unix process control
    # system.
    #
    def running?
      @pid.exist? and Pid.running? @pid.pid
    end

    private

    def log_output?
      options[:log_output] && logdir
    end

    def log_output_syslog?
      options[:log_output_syslog]
    end

    def dir_mode
      @dir_mode or group.dir_mode
    end

    def dir
      @dir or group.dir
    end

    def parse_signals_and_waits(argv)
      unless argv
        return [
          { sig: 'TERM', wait: @force_kill_waittime },
          { sig: 'KILL', wait: 20 }
        ]
      end
      argv.split('|').collect{ |part| splitted = part.split(':'); {sig: splitted[0], wait: splitted[1].to_i}}
    end
  end
end
