Given /^a redis server "([^\"]*)" exists as master$/ do |redis_name|
  TestDaemons::Redis[redis_name].restart
  TestDaemons::Redis[redis_name].master
end

Given /^a redis server "([^\"]*)" exists as slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  TestDaemons::Redis[redis_name].restart
  step "redis server \"#{redis_name}\" is slave of \"#{redis_master_name}\""
end

Given /^redis server "([^\"]*)" is master$/ do |redis_name|
  TestDaemons::Redis[redis_name].master
end

Given /^redis server "([^\"]*)" is slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  TestDaemons::Redis[redis_name].slave_of(TestDaemons::Redis[redis_master_name].port)
  master = TestDaemons::Redis[redis_master_name].redis
  slave = TestDaemons::Redis[redis_name].redis
  begin
    sleep 1
  end while !slave.slave_of?(master.host, master.port)
end

Given /^a redis configuration server using redis servers "([^\"]*)" with clients "([^\"]*)" (?:and confidence level "([^\"]*)" )?exists$/ do |redis_names, redis_configuration_client_names, confidence_level|
  redis_servers = redis_names.split(",").map { |redis_name| TestDaemons::Redis[redis_name].ip_with_port }.join(",")
  TestDaemons::RedisConfigurationServer.start(redis_servers, redis_configuration_client_names, (confidence_level || 100).to_i)
end

Given /^a redis configuration client "([^\"]*)" using redis servers "([^\"]*)" exists$/ do |redis_configuration_client_name, redis_names|
  redis_servers = redis_names.split(",").map do |redis_name|
    TestDaemons::Redis[redis_name].ip_with_port
  end
  TestDaemons::RedisConfigurationClient[redis_configuration_client_name].start
end

Given /^redis server "([^\"]*)" is down$/ do |redis_name|
  TestDaemons::Redis[redis_name].stop
end

Given /^redis configuration client "([^\"]*)" is down$/ do |redis_configuration_client_name|
  TestDaemons::RedisConfigurationClient[redis_configuration_client_name].stop
end

Given /^the retry timeout for the redis master check is reached$/ do
  basetime = Time.now
  i = 0
  while (i <= 10.0) do
    break if TestDaemons::RedisConfigurationClient.instances.values.all? {|instance| File.mtime(instance.redis_master_file) > basetime rescue false}
    i += 0.1
    sleep(0.1)
  end
  sleep 1 # give it time to switch because the modified mtime might be because of the initial invalidation and not the switch
end

Given /^a beetle handler using the redis-master file from "([^\"]*)" exists$/ do |redis_configuration_client_name|
  master_file = redis_master_file(redis_configuration_client_name)
  `ruby features/support/beetle_handler start -- --redis-master-file=#{master_file}`
  assert File.exist?(master_file), "file #{master_file} does not exist"
end

Given /^redis server "([^\"]*)" is down for less seconds than the retry timeout for the redis master check$/ do |redis_name|
  TestDaemons::Redis[redis_name].restart(1)
end

Given /^the retry timeout for the redis master determination is reached$/ do
  sleep 1
end

Given /^redis server "([^\"]*)" is coming back$/ do |redis_name|
  TestDaemons::Redis[redis_name].restart
end

Given /^an old redis master file for "([^\"]*)" with master "([^\"]*)" exists$/ do |redis_configuration_client_name, redis_name|
  master_file = redis_master_file(redis_configuration_client_name)
  File.open(master_file, 'w') do |f|
    f.puts TestDaemons::Redis[redis_name].ip_with_port
  end
end


Then /^the role of redis server "([^\"]*)" should be "(master|slave)"$/ do |redis_name, role|
  expected_role = false
  10.times do
    expected_role = true and break if TestDaemons::Redis[redis_name].__send__ "#{role}?"
    sleep 1
  end
  assert expected_role, "#{redis_name} is not a #{role}"
end

Then /^the redis master of "([^\"]*)" should be "([^\"]*)"$/ do |redis_configuration_client_name, redis_name|
  master_file = redis_master_file(redis_configuration_client_name)
  master = false
  server_info = nil
  10.times do
    server_info = File.read(master_file).chomp if File.exist?(master_file)
    master = true and break if TestDaemons::Redis[redis_name].ip_with_port == server_info
    sleep 1
  end
  assert master, "#{redis_name} is not master of #{redis_configuration_client_name}, master file content: #{server_info.inspect}"
end

Then /^the redis master file of the redis configuration server should contain "([^"]*)"$/ do |redis_name|  # " for emacs :(
  master_file = TestDaemons::RedisConfigurationServer.redis_master_file
  file_contents = File.read(master_file).chomp
  assert_equal TestDaemons::Redis[redis_name].ip_with_port, file_contents
end

Then /^the redis master of "([^\"]*)" should be undefined$/ do |redis_configuration_client_name|
  master_file = redis_master_file(redis_configuration_client_name)
  empty = false
  server_info = nil
  10.times do
    server_info = File.read(master_file).chomp if File.exist?(master_file)
    empty = server_info == ""
    break if empty
    sleep 1
  end
  assert empty, "master file is not empty: #{server_info}"
end

Then /^the redis master of the beetle handler should be "([^\"]*)"$/ do |redis_name|
  Beetle.config.servers = "127.0.0.1:5672" # rabbitmq
  Beetle.config.logger.level = Logger::INFO
  client = Beetle::Client.new.configure :auto_delete => true do |config|
    config.queue(:echo)
    config.message(:echo)
  end
  assert_equal TestDaemons::Redis[redis_name].ip_with_port, client.rpc(:echo, 'nil').second
end

Then /^a system notification for "([^\"]*)" not being available should be sent$/ do |redis_name|
  text = "Redis master '#{TestDaemons::Redis[redis_name].ip_with_port}' not available"
  lines = File.readlines(system_notification_log_path)
  tail = (["","",""]+lines)[-3..-1].join("\n")
  assert_match /#{text}/, tail
end

Then /^a system notification for switching from "([^\"]*)" to "([^\"]*)" should be sent$/ do |old_redis_master_name, new_redis_master_name|
  text = "Setting redis master to '#{TestDaemons::Redis[new_redis_master_name].ip_with_port}' (was '#{TestDaemons::Redis[old_redis_master_name].ip_with_port}')"
  lines = File.readlines(system_notification_log_path)
  assert_match /#{Regexp.escape(text)}/, lines.last
end

Then /^a system notification for no slave available to become new master should be sent$/ do
  text = "Redis master could not be switched, no slave available to become new master"
  lines = File.readlines(system_notification_log_path)
  assert_match /#{text}/, lines.last
end

Then /^the redis configuration server should answer http requests$/ do
  assert TestDaemons::RedisConfigurationServer.answers_text_requests?
  assert TestDaemons::RedisConfigurationServer.answers_html_requests?
  assert TestDaemons::RedisConfigurationServer.answers_json_requests?
end

Given /^an immediate master switch is initiated and responds with (\d+)$/ do |response_code|
  response = TestDaemons::RedisConfigurationServer.initiate_master_switch
  assert_equal response_code, response.code
  sleep 1
end

Then /^the system can run for a while without dying$/ do
  sleep 60
end
