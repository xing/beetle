require 'bundler/setup'
require 'rake/testtask'
require 'bundler/gem_tasks'
require 'cucumber/rake/task'

# 1.8/1.9 compatible way of loading lib/beetle.rb
$:.unshift 'lib'
require 'beetle'

namespace :test do
  task :coverage => :test do
    system 'open coverage/index.html'
  end
end

namespace :beetle do
  task :test do
    Beetle::Client.new.test
  end

  task :trace do
    trap('INT'){ EM.stop_event_loop }
    Beetle::Client.new.trace
  end
end

namespace :rabbit do
  def start(node_name, port, web_port)
    script = File.expand_path(File.dirname(__FILE__)+"/script/start_rabbit")
    # on my machine, the rabbitmq user is not be allowed to access my files.
    # so we need to put the config file under /tmp
    config_file = "/tmp/beetle-testing-rabbitmq-#{node_name}"
    create_config_file config_file, web_port

    enabled_plugins_file = "/tmp/beetle-testing-rabbitmq-enabled-plugins-#{node_name}"
    create_enabled_plugins_file enabled_plugins_file

    puts "starting rabbit #{node_name} on port #{port}, web management port #{web_port}"
    puts "type ^C a RETURN to abort"
    sleep 1
    exec "sudo #{script} #{node_name} #{port} #{config_file} #{enabled_plugins_file}"
  end

  def create_config_file(config_file, web_port)
    File.open("#{config_file}.config",'w') do |f|
      f.puts "["
      f.puts "  {rabbit, [{channel_max, 1000}]},"
      f.puts "  {rabbitmq_management, [{listener, [{port, #{web_port}}]}]}"
      f.puts "]."
    end
  end

  def create_enabled_plugins_file(enabled_plugins_file)
    File.open("#{enabled_plugins_file}",'w') do |f|
      f.puts "[rabbitmq_management]."
    end
  end

  desc "start rabbit instance 1"
  task :start1 do
    start "rabbit1@localhost", 5672, 15672
  end
  desc "start rabbit instance 2"
  task :start2 do
    start "rabbit2@localhost", 5673, 15673
  end
  desc "reset rabbit instances (deletes all data!)"
  task :reset do
     ["rabbit1", "rabbit2"].each do |node|
       `sudo rabbitmqctl -n #{node} stop_app`
       `sudo rabbitmqctl -n #{node} reset`
       `sudo rabbitmqctl -n #{node} start_app`
     end
  end
end

namespace :redis do
  namespace :start do
    def config_file(suffix)
      File.expand_path(File.dirname(__FILE__)+"/etc/redis-#{suffix}.conf")
    end
    desc "start redis master"
    task :master do
      exec "redis-server #{config_file(:master)}"
    end
    desc "start redis slave"
    task :slave do
      exec "redis-server #{config_file(:slave)}"
    end
  end
end

namespace :consul do
  desc "start consul agent in development mode"
  task :start do
    exec "consul agent -dev -node machine"
  end
end

Cucumber::Rake::Task.new(:cucumber) do |t|
  t.cucumber_opts = "features --format progress"
end

task :cucumber => :clean

task :default do
  Rake::Task[:test].invoke
  Rake::Task[:cucumber].invoke
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
  t.warning = false
end

require 'rdoc/task'

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = 'site/rdoc'
  rdoc.title    = 'Beetle'
  rdoc.main     = 'README.rdoc'
  rdoc.options << '--line-numbers' << '--inline-source' << '--quiet'
  rdoc.rdoc_files.include('**/*.rdoc')
  rdoc.rdoc_files.include('MIT-LICENSE')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

task :clean do
  sh "rm -f tmp/*.output tmp/*.log tmp/master-dir/* tmp/slave-dir/* tmp/*lock tmp/*pid test.log"
end
