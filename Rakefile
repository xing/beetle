require 'rake'
require 'rake/testtask'
require 'bundler/gem_tasks'

# rake 0.9.2 hack to supress deprecation warnings caused by cucumber
include Rake::DSL if RAKEVERSION >= "0.9"
require 'cucumber/rake/task'

# 1.8/1.9 compatible way of loading lib/beetle.rb
$:.unshift 'lib'
require 'beetle'

if RUBY_VERSION < "1.9"
  require 'rcov/rcovtask'

  namespace :test do
    namespace :coverage do
      desc "Delete aggregate coverage data."
      task(:clean) { rm_f "coverage.data" }
    end

    desc 'Aggregate code coverage'
    task :coverage => "test:coverage:clean"

    Rcov::RcovTask.new(:coverage) do |t|
      t.libs << "test"
      t.test_files = FileList["test/**/*_test.rb"]
      t.output_dir = "test/coverage"
      t.verbose = true
      t.rcov_opts << "--exclude '.*' --include-file 'lib/beetle/'"
    end
    task :coverage do
      system 'open test/coverage/index.html'
    end if RUBY_PLATFORM =~ /darwin/
  end
else
  namespace :test do
    task :coverage => :test do
      system 'open coverage/index.html'
    end
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
    config_file = File.expand_path(File.dirname(__FILE__)+"/tmp/rabbitmq")

    create_config_file config_file, web_port

    puts "starting rabbit #{node_name} on port #{port}, web management port #{web_port}"
    puts "type ^C a RETURN to abort"
    sleep 1
    exec "sudo #{script} #{node_name} #{port} #{config_file}"
  end

  def create_config_file(config_file, web_port)
    File.open(config_file+".config",'w')  {|f|
        f.write("[\n")
        f.write("{rabbitmq_management, [{listener, [{port, #{web_port}}]}]}\n")
        f.write("].\n")
      }
  end

  desc "start rabbit instance 1"
  task :start1 do
    start "rabbit1", 5672, 15672
  end
  desc "start rabbit instance 2"
  task :start2 do
    start "rabbit2", 5673, 15673
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
  def config_file(suffix)
    File.expand_path(File.dirname(__FILE__)+"/etc/redis-#{suffix}.conf")
  end
  desc "start main redis"
  task :start1 do
    exec "redis-server #{config_file(:master)}"
  end
  desc "start slave redis"
  task :start2 do
    exec "redis-server #{config_file(:slave)}"
  end
end

Cucumber::Rake::Task.new(:cucumber) do |t|
  t.cucumber_opts = "features --format progress"
end

task :default do
  Rake::Task[:test].invoke
  Rake::Task[:cucumber].invoke
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

require 'rdoc/task'

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'site/rdoc'
  rdoc.title    = 'Beetle'
  rdoc.main     = 'README.rdoc'
  rdoc.options << '--line-numbers' << '--inline-source' << '--quiet'
  rdoc.rdoc_files.include('**/*.rdoc')
  rdoc.rdoc_files.include('MIT-LICENSE')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
