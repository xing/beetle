RSpec.describe "(Some) AMQ::Protocol constants" do
  it "include regular port" do
    expect(AMQ::Protocol::DEFAULT_PORT).to eq(5672)
  end

  it "provides TLS/SSL port" do
    expect(AMQ::Protocol::TLS_PORT).to eq(5671)
    expect(AMQ::Protocol::SSL_PORT).to eq(5671)
  end
end
