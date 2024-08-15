require "amq/bit_set"

# extracted from amqp gem. MK.
RSpec.describe AMQ::BitSet do

  #
  # Environment
  #

  let(:nbits) { (1 << 16) - 1 }


  #
  # Examples
  #

  describe "#new" do
    it "has no bits set at the start" do
      bs = AMQ::BitSet.new(128)
      0.upto(127) do |i|
        expect(bs[i]).to be_falsey
      end
    end # it
  end # describe

  describe "#word_index" do
    subject do
      described_class.new(nbits)
    end
    it "returns 0 when the word is between 0 and 63" do
      expect(subject.word_index(0)).to eq(0)
      expect(subject.word_index(63)).to eq(0)
    end # it
    it "returns 1 when the word is between 64 and 127" do
      expect(subject.word_index(64)).to be(1)
      expect(subject.word_index(127)).to be(1)
    end # it
    it "returns 2 when the word is between 128 and another number" do
      expect(subject.word_index(128)).to be(2)
    end # it
  end # describe

  describe "#get, #[]" do
    describe "when bit at given position is set" do
      subject do
        o = described_class.new(nbits)
        o.set(3)
        o
      end

      it "returns true" do
        expect(subject.get(3)).to be_truthy
      end # it
    end # describe

    describe "when bit at given position is off" do
      subject do
        described_class.new(nbits)
      end

      it "returns false" do
        expect(subject.get(5)).to be_falsey
      end # it
    end # describe

    describe "when index out of range" do
      subject do
        described_class.new(nbits)
      end

      it "should raise IndexError for negative index" do
        expect { subject.get(-1) }.to raise_error(IndexError)
      end # it
      it "should raise IndexError for index >= number of bits" do
        expect { subject.get(nbits) }.to raise_error(IndexError)
      end # it
    end # describe
  end # describe


  describe "#set" do
    describe "when bit at given position is set" do
      subject do
        described_class.new(nbits)
      end

      it "has no effect" do
        subject.set(3)
        expect(subject.get(3)).to be_truthy
        subject.set(3)
        expect(subject[3]).to be_truthy
      end # it
    end # describe

    describe "when bit at given position is off" do
      subject do
        described_class.new(nbits)
      end

      it "sets that bit" do
        subject.set(3)
        expect(subject.get(3)).to be_truthy

        subject.set(33)
        expect(subject.get(33)).to be_truthy

        subject.set(3387)
        expect(subject.get(3387)).to be_truthy
      end # it
    end # describe

    describe "when index out of range" do
      subject do
        described_class.new(nbits)
      end

      it "should raise IndexError for negative index" do
        expect { subject.set(-1) }.to raise_error(IndexError)
      end # it
      it "should raise IndexError for index >= number of bits" do
        expect { subject.set(nbits) }.to raise_error(IndexError)
      end # it
    end # describe
  end # describe


  describe "#unset" do
    describe "when bit at a given position is set" do
      subject do
        described_class.new(nbits)
      end

      it "unsets that bit" do
        subject.set(3)
        expect(subject.get(3)).to be_truthy
        subject.unset(3)
        expect(subject.get(3)).to be_falsey
      end # it
    end # describe


    describe "when bit at a given position is off" do
      subject do
        described_class.new(nbits)
      end

      it "has no effect" do
        expect(subject.get(3)).to be_falsey
        subject.unset(3)
        expect(subject.get(3)).to be_falsey
      end # it
    end # describe

    describe "when index out of range" do
      subject do
        described_class.new(nbits)
      end

      it "should raise IndexError for negative index" do
        expect { subject.unset(-1) }.to raise_error(IndexError)
      end # it
      it "should raise IndexError for index >= number of bits" do
        expect { subject.unset(nbits) }.to raise_error(IndexError)
      end # it
    end # describe
  end # describe



  describe "#clear" do
    subject do
      described_class.new(nbits)
    end

    it "clears all bits" do
      subject.set(3)
      expect(subject.get(3)).to be_truthy

      subject.set(7668)
      expect(subject.get(7668)).to be_truthy

      subject.clear

      expect(subject.get(3)).to be_falsey
      expect(subject.get(7668)).to be_falsey
    end # it
  end # describe

  describe "#number_of_trailing_ones" do
    it "calculates them" do
      expect(described_class.number_of_trailing_ones(0)).to eq(0)
      expect(described_class.number_of_trailing_ones(1)).to eq(1)
      expect(described_class.number_of_trailing_ones(2)).to eq(0)
      expect(described_class.number_of_trailing_ones(3)).to eq(2)
      expect(described_class.number_of_trailing_ones(4)).to eq(0)
    end # it
  end # describe

  describe '#next_clear_bit' do
    subject do
      described_class.new(255)
    end
    it "returns sequential values when none have been returned" do
      expect(subject.next_clear_bit).to eq(0)
      subject.set(0)
      expect(subject.next_clear_bit).to eq(1)
      subject.set(1)
      expect(subject.next_clear_bit).to eq(2)
      subject.unset(1)
      expect(subject.next_clear_bit).to eq(1)
    end # it

    it "returns the same number as long as nothing is set" do
      expect(subject.next_clear_bit).to eq(0)
      expect(subject.next_clear_bit).to eq(0)
    end # it

    it "handles more than 128 bits" do
      0.upto(254) do |i|
        subject.set(i)
        expect(subject.next_clear_bit).to eq(i + 1)
      end
      subject.unset(254)
      expect(subject.get(254)).to be_falsey
    end # it
  end # describe
end
