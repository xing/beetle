require "amq/settings"

RSpec.describe AMQ::Settings do
  describe ".default" do
    it "should provide some default values" do
      expect(AMQ::Settings.default).to_not be_nil
      expect(AMQ::Settings.default[:host]).to_not be_nil
    end
  end

  describe ".configure(&block)" do
    it "should merge custom settings with default settings" do
      settings = AMQ::Settings.configure(:host => "tagadab")
      expect(settings[:host]).to eql("tagadab")
    end

    it "should merge custom settings from AMQP URL with default settings" do
      settings = AMQ::Settings.configure("amqp://tagadab")
      expect(settings[:host]).to eql("tagadab")
    end
  end
end
