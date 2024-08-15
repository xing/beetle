require 'time'
require "amq/protocol/table_value_decoder"

module AMQ
  module Protocol
    RSpec.describe TableValueDecoder do

      it "is capable of decoding basic arrays TableValueEncoder encodes" do
        input1 = [1, 2, 3]

        value, _offset = described_class.decode_array(TableValueEncoder.encode(input1), 1)
        expect(value.size).to eq(3)
        expect(value.first).to eq(1)
        expect(value).to eq(input1)



        input2 = ["one", 2, "three"]

        value, _offset = described_class.decode_array(TableValueEncoder.encode(input2), 1)
        expect(value.size).to eq(3)
        expect(value.first).to eq("one")
        expect(value).to eq(input2)



        input3 = ["one", 2, "three", 4.0, 5000000.0]

        value, _offset = described_class.decode_array(TableValueEncoder.encode(input3), 1)
        expect(value.size).to eq(5)
        expect(value.last).to eq(5000000.0)
        expect(value).to eq(input3)
      end



      it "is capable of decoding arrays TableValueEncoder encodes" do
        input1 = [{ "one" => 2 }, 3]
        data1  = TableValueEncoder.encode(input1)

        # puts(TableValueEncoder.encode({ "one" => 2 }).inspect)
        # puts(TableValueEncoder.encode(input1).inspect)


        value, _offset = described_class.decode_array(data1, 1)
        expect(value.size).to eq(2)
        expect(value.first).to eq(Hash["one" => 2])
        expect(value).to eq(input1)



        input2 = ["one", 2, { "three" => { "four" => 5.0 } }]

        value, _offset = described_class.decode_array(TableValueEncoder.encode(input2), 1)
        expect(value.size).to eq(3)
        expect(value.last["three"]["four"]).to eq(5.0)
        expect(value).to eq(input2)
      end

      it "is capable of decoding 32 bit float values" do
        input = Float32Bit.new(10.0)
        data  = TableValueEncoder.encode(input)

        value = described_class.decode_32bit_float(data, 1)[0]
        expect(value).to eq(10.0)
      end

      context "8bit/byte decoding" do
        let(:examples) {
          {
              0x00 => "\x00",
              0x01 => "\x01",
              0x10 => "\x10",
              255   => "\xFF" # not -1
          }
        }

        it "is capable of decoding byte values" do
          examples.each do |key, value|
            expect(described_class.decode_byte(value, 0).first).to eq(key)
          end
        end
      end
    end
  end
end
