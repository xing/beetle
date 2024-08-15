RSpec.describe AMQ::Protocol::Method, ".encode_body" do
  it "encodes 1-byte long payload as exactly 1 body frame" do
    expect(described_class.encode_body('1', 1, 65536).size).to eq(1)
  end

  it "encodes 0-byte long (blank) payload as exactly 0 body frame" do
    expect(described_class.encode_body('', 1, 65536).size).to eq(0)
  end
end
