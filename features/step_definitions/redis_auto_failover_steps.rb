Given /^a redis server "([^\"]*)" exists as master$/ do |redis_name|
  TestDaemons::Redis[redis_name].start
  TestDaemons::Redis[redis_name].master
end

Given /^a redis server "([^\"]*)" exists as slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  TestDaemons::Redis[redis_name].start
  Given "redis server \"#{redis_name}\" is slave of \"#{redis_master_name}\""
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

Given /^a redis configuration server using redis servers "([^\"]*)" with clients "([^\"]*)" exists$/ do |redis_names, redis_configuration_client_names|
  redis_servers = redis_names.split(",").map { |redis_name| TestDaemons::Redis[redis_name].ip_with_port }.join(",")
  TestDaemons::RedisConfigurationServer.start(redis_servers, redis_configuration_client_names)
end

Given /^a redis configuration client "([^\"]*)" using redis servers "([^\"]*)" exists$/ do |redis_configuration_client_name, redis_names|
  redis_servers = redis_names.split(",").map do |redis_name|
    TestDaemons::Redis[redis_name].ip_with_port
  end
  TestDaemons::RedisConfigurationClient.find_or_initialize_by_name(redis_configuration_client_name, redis_servers).start
end

Given /^redis server "([^\"]*)" is down$/ do |redis_name|
  TestDaemons::Redis[redis_name].stop
end

Given /^the retry timeout for the redis master check is reached$/ do
  sleep 10
end

Given /^a beetle handler using the redis-master file from "([^\"]*)" exists$/ do |redis_configuration_client_name|
  master_file = redis_master_file(redis_configuration_client_name)
  `ruby features/support/beetle_handler start -- --redis-master-file=#{master_file}`
  assert File.exist?(master_file), "file #{master_file} does not exist"
end

Given /^redis server "([^\"]*)" is down for less seconds than the retry timeout for the redis master check$/ do |redis_name|
  TestDaemons::Redis[redis_name].restart(1)
end

Given /^the first redis configuration client is not able to send the client_invalidated message$/ do
  # we kill the redis configuration process brutally, so that it cannot send an offline message before exit
  Process.kill("KILL", first_redis_configuration_client_pid)
end

Given /^a reconfiguration round is in progress$/ do
  pending # express the regexp above with the code you wish you had
end

Given /^the retry timeout for the redis master determination is reached$/ do
  sleep 1
end

Given /^redis server "([^\"]*)" is coming back$/ do |redis_name|
  TestDaemons::Redis[redis_name].start
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
  raise "#{redis_name} is not a #{role}" unless expected_role
end

Then /^the redis master of "([^\"]*)" should be "([^\"]*)"$/ do |redis_configuration_client_name, redis_name|
  master_file = redis_master_file(redis_configuration_client_name)
  master = false
  10.times do
    server_info = File.read(master_file).chomp
    master = true and break if TestDaemons::Redis[redis_name].ip_with_port == server_info
    sleep 1
  end
  raise "#{redis_name} is not master of #{redis_configuration_client_name}" unless master
end

Then /^the redis master of "([^\"]*)" should be undefined$/ do |redis_configuration_client_name|
  master_file = redis_master_file(redis_configuration_client_name)
  assert_equal "", File.read(master_file).chomp
end

Then /^the redis master of the beetle handler should be "([^\"]*)"$/ do |redis_name|
  Beetle.config.servers = "localhost:5672, localhost:5673" # rabbitmq
  Beetle.config.logger.level = Logger::INFO
  client = Beetle::Client.new
  client.register_queue(:echo)
  client.register_message(:echo)
  assert_equal TestDaemons::Redis[redis_name].ip_with_port, client.rpc(:echo, 'nil').second
end

Then /^a system notification for "([^\"]*)" not being available should be sent$/ do |redis_name|
  text = "Redis master '#{TestDaemons::Redis[redis_name].ip_with_port}' not available"
  assert_match /#{text}/, File.readlines(system_notification_log_path).last
end

Then /^a system notification for switching from "([^\"]*)" to "([^\"]*)" should be sent$/ do |old_redis_master_name, new_redis_master_name|
  text = "Redis master switched from '#{TestDaemons::Redis[old_redis_master_name].ip_with_port}' to '#{TestDaemons::Redis[new_redis_master_name].ip_with_port}'"
  assert_match /#{text}/, File.read(system_notification_log_path)
end

Then /^a system notification for no slave available to become new master should be sent$/ do
  text = "Redis master could not be switched, no slave available to become new master"
  assert_match /#{text}/, File.readlines(system_notification_log_path).last
end
