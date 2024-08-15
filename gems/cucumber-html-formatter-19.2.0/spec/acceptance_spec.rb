require 'cucumber-compatibility-kit'
require 'cucumber/html_formatter'

describe Cucumber::HTMLFormatter.name do

  Cucumber::CompatibilityKit.gherkin_examples.each do |example_name|
    def run_formatter(messages)
      out = StringIO.new
      formatter = Cucumber::HTMLFormatter::Formatter.new(out)
      formatter.process_messages(messages)
      out.string
    end

    describe "'#{example_name}' example" do
      subject(:html_report) { run_formatter(File.readlines(example_ndjson)) }

      let(:example_ndjson) { "#{Cucumber::CompatibilityKit.example_path(example_name)}/#{example_name}.feature.ndjson" }

      it { is_expected.to match(/\A<!DOCTYPE html>\s?<html/) }
      it { is_expected.to match(/<\/html>\Z/) }
    end
  end

  Cucumber::CompatibilityKit.markdown_examples.each do |example_name|
    describe "'#{example_name}' example" do
      let(:example_ndjson) { "#{Cucumber::CompatibilityKit.example_path(example_name)}/#{example_name}.feature.md.ndjson" }
      subject(:html_report) { run_formatter(File.readlines(example_ndjson)) }

      it { is_expected.to match(/\A<!DOCTYPE html>\s?<html/) }
      it { is_expected.to match(/<\/html>\Z/) }
    end
  end
end
