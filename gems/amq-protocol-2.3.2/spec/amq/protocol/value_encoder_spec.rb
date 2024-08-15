require 'time'
require "amq/protocol/table_value_encoder"
require "amq/protocol/float_32bit"

module AMQ
  module Protocol
    RSpec.describe TableValueEncoder do

      it "calculates size of string field values" do
        expect(described_class.field_value_size("amqp")).to eq(9)
        expect(described_class.encode("amqp").bytesize).to eq(9)

        expect(described_class.field_value_size("amq-protocol")).to eq(17)
        expect(described_class.encode("amq-protocol").bytesize).to eq(17)

        expect(described_class.field_value_size("à bientôt")).to eq(16)
        expect(described_class.encode("à bientôt").bytesize).to eq(16)
      end

      it "calculates size of integer field values" do
        expect(described_class.field_value_size(10)).to eq(9)
        expect(described_class.encode(10).bytesize).to eq(9)
      end

      it "calculates size of float field values (considering them to be 64-bit)" do
        expect(described_class.field_value_size(10.0)).to eq(9)
        expect(described_class.encode(10.0).bytesize).to eq(9)

        expect(described_class.field_value_size(120000.0)).to eq(9)
        expect(described_class.encode(120000.0).bytesize).to eq(9)
      end

      it "calculates size of float field values (boxed as 32-bit)" do
        expect(described_class.encode(AMQ::Protocol::Float32Bit.new(10.0)).bytesize).to eq(5)
        expect(described_class.encode(AMQ::Protocol::Float32Bit.new(120000.0)).bytesize).to eq(5)
      end

      it "calculates size of boolean field values" do
        expect(described_class.field_value_size(true)).to eq(2)
        expect(described_class.encode(true).bytesize).to eq(2)

        expect(described_class.field_value_size(false)).to eq(2)
        expect(described_class.encode(false).bytesize).to eq(2)
      end

      it "calculates size of void field values" do
        expect(described_class.field_value_size(nil)).to eq(1)
        expect(described_class.encode(nil).bytesize).to eq(1)
      end

      it "calculates size of time field values" do
        t = Time.parse("2011-07-14 01:17:46 +0400")

        expect(described_class.field_value_size(t)).to eq(9)
        expect(described_class.encode(t).bytesize).to eq(9)
      end


      it "calculates size of basic table field values" do
        input1   = { "key" => "value" }
        expect(described_class.field_value_size(input1)).to eq(19)
        expect(described_class.encode(input1).bytesize).to eq(19)


        input2   = { "intval" => 1 }
        expect(described_class.field_value_size(input2)).to eq(21)
        expect(described_class.encode(input2).bytesize).to eq(21)


        input3   = { "intval" => 1, "key" => "value" }
        expect(described_class.field_value_size(input3)).to eq(35)
        expect(described_class.encode(input3).bytesize).to eq(35)
      end


      it "calculates size of table field values" do
        input1   = {
          "hashval"    => {
            "protocol" => {
              "name"  => "AMQP",
              "major" => 0,
              "minor" => "9",
              "rev"   => 1.0,
              "spec"  => {
                "url"  => "http://bit.ly/hw2ELX",
                "utf8" => "à bientôt".force_encoding(::Encoding::ASCII_8BIT)
              }
            },
            "true"     => true,
            "false"    => false,
            "nil"      => nil
          }
        }

        expect(described_class.field_value_size(input1)).to eq(166)
        # puts(described_class.encode(input1).inspect)
        expect(described_class.encode(input1).bytesize).to eq(166)



        input2   = {
          "boolval"      => true,
          "intval"       => 1,
          "strval"       => "Test",
          "timestampval" => Time.parse("2011-07-14 01:17:46 +0400"),
          "floatval"     => 3.14,
          "longval"      => 912598613,
          "hashval"      => { "protocol" => "AMQP091", "true" => true, "false" => false, "nil" => nil }
        }

        expect(described_class.field_value_size(input2)).to eq(158)
        expect(described_class.encode(input2).bytesize).to eq(158)
      end

      it "calculates size of basic array field values" do
        input1 = [1, 2, 3]

        expect(described_class.field_value_size(input1)).to eq(32)
        expect(described_class.encode(input1).bytesize).to eq(32)


        input2 = ["one", "two", "three"]
        expect(described_class.field_value_size(input2)).to eq(31)
        expect(described_class.encode(input2).bytesize).to eq(31)


        input3 = ["one", 2, "three"]
        expect(described_class.field_value_size(input3)).to eq(32)
        expect(described_class.encode(input3).bytesize).to eq(32)


        input4 = ["one", 2, "three", ["four", 5, [6.0]]]
        expect(described_class.field_value_size(input4)).to eq(69)
        expect(described_class.encode(input4).bytesize).to eq(69)
      end


    end # TableValueEncoder
  end # Protocol
end # AMQ
