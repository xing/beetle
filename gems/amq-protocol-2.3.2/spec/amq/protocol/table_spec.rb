require 'bigdecimal'
require 'time'

module AMQ
  module Protocol
    RSpec.describe Table do
      timestamp    = Time.utc(2010, 12, 31, 23, 58, 59)
      bigdecimal_1 = BigDecimal("1.0")
      bigdecimal_2 = BigDecimal("5E-3")

      DATA = {
          {}                       => "\x00\x00\x00\x00",
          {"test" => 1}            => "\x00\x00\x00\x0E\x04testl\x00\x00\x00\x00\x00\x00\x00\x01",
          {"float" => 1.92}        => "\x00\x00\x00\x0F\x05floatd?\xFE\xB8Q\xEB\x85\x1E\xB8",
          {"test" => "string"}     => "\x00\x00\x00\x10\x04testS\x00\x00\x00\x06string",
          {"test" => {}}           => "\x00\x00\x00\n\x04testF\x00\x00\x00\x00",
          {"test" => bigdecimal_1} => "\x00\x00\x00\v\x04testD\x00\x00\x00\x00\x01",
          {"test" => bigdecimal_2} => "\x00\x00\x00\v\x04testD\x03\x00\x00\x00\x05",
          {"test" => timestamp}    => "\x00\x00\x00\x0e\x04testT\x00\x00\x00\x00M\x1enC"
      }

      describe ".encode" do
        it "should return \"\x00\x00\x00\x00\" for nil" do
          encoded_value = "\x00\x00\x00\x00"

          expect(Table.encode(nil)).to eql(encoded_value)
        end

        it "should serialize { :test => true }" do
          expect(Table.encode(:test => true)).
            to eql("\x00\x00\x00\a\x04testt\x01".force_encoding(Encoding::ASCII_8BIT))
        end

        it "should serialize { :test => false }" do
          expect(Table.encode(:test => false)).
            to eql("\x00\x00\x00\a\x04testt\x00".force_encoding(Encoding::ASCII_8BIT))
        end

        it "should serialize { :coordinates => { :latitude  => 59.35 } }" do
          expect(Table.encode(:coordinates => { :latitude  => 59.35 })).
            to eql("\x00\x00\x00#\vcoordinatesF\x00\x00\x00\x12\blatituded@M\xAC\xCC\xCC\xCC\xCC\xCD".force_encoding(Encoding::ASCII_8BIT))
        end

        it "should serialize { :coordinates => { :longitude => 18.066667 } }" do
          expect(Table.encode(:coordinates => { :longitude => 18.066667 })).
            to eql("\x00\x00\x00$\vcoordinatesF\x00\x00\x00\x13\tlongituded@2\x11\x11\x16\xA8\xB8\xF1".force_encoding(Encoding::ASCII_8BIT))
        end

        it "should serialize long UTF-8 strings and symbols" do
          long_utf8 = "à" * 192
          long_ascii8 = long_utf8.dup.force_encoding(::Encoding::ASCII_8BIT)

          input = { "utf8_string" => long_utf8, "utf8_symbol" => long_utf8.to_sym }
          output = { "utf8_string" => long_ascii8, "utf8_symbol" => long_ascii8 }

          expect(Table.decode(Table.encode(input))).to eq(output)
        end

        DATA.each do |data, encoded|
          it "should return #{encoded.inspect} for #{data.inspect}" do
            expect(Table.encode(data)).to eql(encoded.force_encoding(Encoding::ASCII_8BIT))
          end
        end
      end

      describe ".decode" do
        DATA.each do |data, encoded|
          it "should return #{data.inspect} for #{encoded.inspect}" do
            expect(Table.decode(encoded)).to eql(data)
          end

          it "is capable of decoding what it encodes" do
            expect(Table.decode(Table.encode(data))).to eq(data)
          end
        end # DATA.each


        it "is capable of decoding boolean table values" do
          input1   = { "boolval" => true }
          expect(Table.decode(Table.encode(input1))).to eq(input1)


          input2   = { "boolval" => false }
          expect(Table.decode(Table.encode(input2))).to eq(input2)
        end


        it "is capable of decoding nil table values" do
          input   = { "nilval" => nil }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end

        it "is capable of decoding nil table in nested hash/map values" do
          input   = { "hash" => {"nil" => nil} }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end

        it "is capable of decoding string table values" do
          input   = { "stringvalue" => "string" }
          expect(Table.decode(Table.encode(input))).to eq(input)

          expect(Table.decode("\x00\x00\x00\x17\vstringvalueS\x00\x00\x00\x06string")).to eq(input)
        end

        it "is capable of decoding byte array table values (as Ruby strings)" do
          expect(Table.decode("\x00\x00\x00\x17\vstringvaluex\x00\x00\x00\x06string")).to eq({"stringvalue" => "string"})
        end

        it "is capable of decoding string table values with UTF-8 characters" do
          input   = {
            "строка".force_encoding(::Encoding::ASCII_8BIT) => "значение".force_encoding(::Encoding::ASCII_8BIT)
          }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end


        it "is capable of decoding integer table values" do
          input   = { "intvalue" => 10 }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end


        it "is capable of decoding signed integer table values" do
          input   = { "intvalue" => -10 }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end


        it "is capable of decoding long table values" do
          input   = { "longvalue" => 912598613 }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end



        it "is capable of decoding float table values" do
          input   = { "floatvalue" => 100.0 }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end



        it "is capable of decoding time table values" do
          input   = { "intvalue" => Time.parse("2011-07-14 01:17:46 +0400") }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end



        it "is capable of decoding empty hash table values" do
          input   = { "hashvalue" => Hash.new }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end



        it "is capable of decoding empty array table values" do
          input   = { "arrayvalue" => Array.new }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end


        it "is capable of decoding single string value array table values" do
          input   = { "arrayvalue" => ["amq-protocol"] }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end



        it "is capable of decoding simple nested hash table values" do
          input   = { "hashvalue" => { "a" => "b" } }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end



        it "is capable of decoding nil table values" do
          input   = { "nil" => nil }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end

        it 'is capable of decoding 8bit signed integers' do
          output = TableValueDecoder.decode_byte("\xC0",0).first
          expect(output).to eq(192)
        end

        it 'is capable of decoding 16bit signed integers' do
          output = TableValueDecoder.decode_short("\x06\x8D", 0).first
          expect(output).to eq(1677)
        end

        it "is capable of decoding tables" do
          input   = {
            "boolval"      => true,
            "intval"       => 1,
            "strval"       => "Test",
            "timestampval" => Time.parse("2011-07-14 01:17:46 +0400"),
            "floatval"     => 3.14,
            "longval"      => 912598613,
            "hashval"      => { "protocol" => "AMQP091", "true" => true, "false" => false, "nil" => nil }
          }
          expect(Table.decode(Table.encode(input))).to eq(input)
        end



        it "is capable of decoding deeply nested tables" do
          input   = {
            "hashval"    => {
              "protocol" => {
                "name"  => "AMQP",
                "major" => 0,
                "minor" => "9",
                "rev"   => 1.0,
                "spec"  => {
                  "url"  => "http://bit.ly/hw2ELX",
                  "utf8" => "à bientôt"
                }
              },
              "true"     => true,
              "false"    => false,
              "nil"      => nil
            }
          }
          expect(Table.decode(Table.encode(input))).to eq(input.tap { |r| r["hashval"]["protocol"]["spec"]["utf8"].force_encoding(::Encoding::ASCII_8BIT) })
        end



        it "is capable of decoding array values in tables" do
          input1   = {
            "arrayval1" => [198, 3, 77, 8.0, ["inner", "array", { "oh" => "well", "it" => "should work", "3" => 6 }], "two", { "a" => "value", "is" => nil }],
            "arrayval2" => [198, 3, 77, "two", { "a" => "value", "is" => nil }, 8.0, ["inner", "array", { "oh" => "well", "it" => "should work", "3" => 6 }]]
          }
          expect(Table.decode(Table.encode(input1))).to eq(input1)

          now = Time.now
          input2 = {
                       "coordinates" => {
                         "latitude"  => 59.35,
                         "longitude" => 18.066667
                       },
                       "participants" => 11,
                       "venue"        => "Stockholm",
                       "true_field"   => true,
                       "false_field"  => false,
                       "nil_field"    => nil,
                       "ary_field"    => ["one", 2.0, 3]
                     }

          expect(Table.decode(Table.encode(input2))).to eq(input2)

          input3 = { "timely" => { "now" => now } }
          expect(Table.decode(Table.encode(input3))["timely"]["now"].to_i).to eq(now.to_i)
        end

      end # describe
    end
  end
end
