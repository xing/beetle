require "amq/int_allocator"

RSpec.describe AMQ::IntAllocator do

  #
  # Environment
  #

  subject do
    described_class.new(1, 5)
  end


  # ...


  #
  # Examples
  #

  describe "#number_of_bits" do
    it "returns number of bits available for allocation" do
      expect(subject.number_of_bits).to eq(4)
    end
  end


  describe "#hi" do
    it "returns upper bound of the allocation range" do
      expect(subject.hi).to eq(5)
    end
  end

  describe "#lo" do
    it "returns lower bound of the allocation range" do
      expect(subject.lo).to eq(1)
    end
  end


  describe "#allocate" do
    context "when integer in the range is available" do
      it "returns allocated integer" do
        expect(subject.allocate).to eq(1)
        expect(subject.allocate).to eq(2)
        expect(subject.allocate).to eq(3)
        expect(subject.allocate).to eq(4)

        expect(subject.allocate).to eq(-1)
      end
    end

    context "when integer in the range IS NOT available" do
      it "returns -1" do
        4.times { subject.allocate }

        expect(subject.allocate).to eq(-1)
        expect(subject.allocate).to eq(-1)
        expect(subject.allocate).to eq(-1)
        expect(subject.allocate).to eq(-1)
      end
    end
  end


  describe "#free" do
    context "when the integer WAS allocated" do
      it "returns frees that integer" do
        4.times { subject.allocate }
        expect(subject.allocate).to eq(-1)

        subject.free(1)
        expect(subject.allocate).to eq(1)
        expect(subject.allocate).to eq(-1)
        subject.free(2)
        expect(subject.allocate).to eq(2)
        expect(subject.allocate).to eq(-1)
        subject.free(3)
        expect(subject.allocate).to eq(3)
        expect(subject.allocate).to eq(-1)
      end
    end

    context "when the integer WAS NOT allocated" do
      it "has no effect" do
        32.times { subject.free(1) }
        expect(subject.allocate).to eq(1)
      end
    end
  end


  describe "#allocated?" do
    context "when given position WAS allocated" do
      it "returns true" do
        3.times { subject.allocate }

        expect(subject.allocated?(1)).to be_truthy
        expect(subject.allocated?(2)).to be_truthy
        expect(subject.allocated?(3)).to be_truthy
      end
    end

    context "when given position WAS NOT allocated" do
      it "returns false" do
        2.times { subject.allocate }

        expect(subject.allocated?(3)).to be_falsey
        expect(subject.allocated?(4)).to be_falsey
      end
    end
  end
end
