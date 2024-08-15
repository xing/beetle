require "amq/uri"

# https://www.rabbitmq.com/uri-spec.html
# http://www.ietf.org/rfc/rfc3986.txt
# https://tools.ietf.org/rfc/rfc5246.txt

RSpec.describe AMQ::URI do
  describe ".parse" do
    subject { described_class.parse(uri) }

    context "schema is not amqp or amqps" do
      let(:uri) { "http://rabbitmq" }

      it "raises ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, /amqp or amqps schema/)
      end
    end

    describe "host" do
      context "present" do
        let(:uri) { "amqp://rabbitmq" }

        it "parses host" do
          expect(subject[:host]).to eq("rabbitmq")
        end
      end

      if RUBY_VERSION >= "2.2"
        context "absent" do
          let(:uri) { "amqp://" }

          # Note that according to the ABNF, the host component may not be absent, but it may be zero-length.
          it "falls back to default nil host" do
            expect(subject[:host]).to be_nil
          end
        end
      end

      if RUBY_VERSION < "2.2"
        context "absent" do
          let(:uri) { "amqp://" }

          # Note that according to the ABNF, the host component may not be absent, but it may be zero-length.
          it "raises InvalidURIError" do
            expect { subject[:host] }.to raise_error(URI::InvalidURIError, /bad URI\(absolute but no path\)/)
          end
        end
      end
    end

    describe "port" do
      context "present" do
        let(:uri) { "amqp://rabbitmq:5672" }

        it "parses port" do
          expect(subject[:port]).to eq(5672)
        end
      end

      context "absent" do
        context "schema amqp" do
          let(:uri) { "amqp://rabbitmq" }

          it "falls back to 5672 port" do
            expect(subject[:port]).to eq(5672)
          end
        end

        context "schema amqps" do
          let(:uri) { "amqps://rabbitmq" }

          it "falls back to 5671 port" do
            expect(subject[:port]).to eq(5671)
          end
        end
      end
    end

    describe "username and passowrd" do
      context "both present" do
        let(:uri) { "amqp://alpha:beta@rabbitmq" }

        it "parses user and pass" do
          expect(subject[:user]).to eq("alpha")
          expect(subject[:pass]).to eq("beta")
        end
      end

      context "only username present" do
        let(:uri) { "amqp://alpha@rabbitmq" }

        it "parses user and falls back to nil pass" do
          expect(subject[:user]).to eq("alpha")
          expect(subject[:pass]).to be_nil
        end

        context "with ':'" do
          let(:uri) { "amqp://alpha:@rabbitmq" }

          it "parses user and falls back to "" (empty) pass" do
            expect(subject[:user]).to eq("alpha")
            expect(subject[:pass]).to eq("")
          end
        end
      end

      context "only password present" do
        let(:uri) { "amqp://:beta@rabbitmq" }

        it "parses pass and falls back to "" (empty) user" do
          expect(subject[:user]).to eq("")
          expect(subject[:pass]).to eq("beta")
        end
      end

      context "both absent" do
        let(:uri) { "amqp://rabbitmq" }

        it "falls back to nil user and pass" do
          expect(subject[:user]).to be_nil
          expect(subject[:pass]).to be_nil
        end

        context "with ':'" do
          let(:uri) { "amqp://:@rabbitmq" }

          it "falls back to "" (empty) user and "" (empty) pass" do
            expect(subject[:user]).to eq("")
            expect(subject[:pass]).to eq("")
          end
        end
      end

      context "%-encoded" do
        let(:uri) { "amqp://%61lpha:bet%61@rabbitmq" }

        it "parses user and pass" do
          expect(subject[:user]).to eq("alpha")
          expect(subject[:pass]).to eq("beta")
        end
      end
    end

    describe "path" do
      context "present" do
        let(:uri) { "amqp://rabbitmq/staging" }

        it "parses vhost" do
          expect(subject[:vhost]).to eq("staging")
        end

        context "with dots" do
          let(:uri) { "amqp://rabbitmq/staging.critical.subsystem-a" }

          it "parses vhost" do
            expect(subject[:vhost]).to eq("staging.critical.subsystem-a")
          end
        end

        context "with slashes" do
          let(:uri) { "amqp://rabbitmq/staging/critical/subsystem-a" }

          it "raises ArgumentError" do
            expect { subject[:vhost] }.to raise_error(ArgumentError)
          end
        end

        context "with trailing slash" do
          let(:uri) { "amqp://rabbitmq/" }

          it "parses vhost as an empty string" do
            expect(subject[:vhost]).to eq("")
          end
        end

        context "with trailing %-encoded slashes" do
          let(:uri) { "amqp://rabbitmq/%2Fstaging" }

          it "parses vhost as string with leading slash" do
            expect(subject[:vhost]).to eq("/staging")
          end
        end

        context "%-encoded" do
          let(:uri) { "amqp://rabbitmq/%2Fstaging%2Fcritical%2Fsubsystem-a" }

          it "parses vhost as string with leading slash" do
            expect(subject[:vhost]).to eq("/staging/critical/subsystem-a")
          end
        end
      end

      context "absent" do
        let(:uri) { "amqp://rabbitmq" }

        it "falls back to default nil vhost" do
          expect(subject[:vhost]).to be_nil
        end
      end
    end

    describe "query parameters" do
      context "present" do
        let(:uri) { "amqp://rabbitmq?heartbeat=10&connection_timeout=100&channel_max=1000&auth_mechanism=plain&auth_mechanism=amqplain" }

        it "parses client connection parameters" do
          expect(subject[:heartbeat]).to eq(10)
          expect(subject[:connection_timeout]).to eq(100)
          expect(subject[:channel_max]).to eq(1000)
          expect(subject[:auth_mechanism]).to eq(["plain", "amqplain"])
        end
      end

      context "absent" do
        let(:uri) { "amqp://rabbitmq" }

        it "falls back to default client connection parameters" do
          expect(subject[:heartbeat]).to be_nil
          expect(subject[:connection_timeout]).to be_nil
          expect(subject[:channel_max]).to be_nil
          expect(subject[:auth_mechanism]).to be_empty
        end
      end

      context "schema amqp" do
        context "tls parameters" do
          %w(verify fail_if_no_peer_cert cacertfile certfile keyfile).each do |tls_param|
            describe "#{tls_param}" do
              let(:uri) { "amqp://rabbitmq?#{tls_param}=value" }

              it "raises ArgumentError" do
                expect { subject }.to raise_error(ArgumentError, /The option '#{tls_param}' can only be used in URIs that use amqps schema/)
              end
            end
          end
        end
      end

      context "amqpa schema" do
        context "TLS parameters in query string" do
          context "case 1" do
            let(:uri) { "amqps://rabbitmq?verify=true&fail_if_no_peer_cert=true&cacertfile=/examples/tls/cacert.pem&certfile=/examples/tls/client_cert.pem&keyfile=/examples/tls/client_key.pem" }

            it "parses tls options" do
              expect(subject[:verify]).to be_truthy
              expect(subject[:fail_if_no_peer_cert]).to be_truthy
              expect(subject[:cacertfile]).to eq("/examples/tls/cacert.pem")
              expect(subject[:certfile]).to eq("/examples/tls/client_cert.pem")
              expect(subject[:keyfile]).to eq("/examples/tls/client_key.pem")
            end
          end

          context "case 2" do
            let(:uri) { "amqps://bunny_gem:bunny_password@/bunny_testbed?heartbeat=10&connection_timeout=100&channel_max=1000&verify=false&cacertfile=spec/tls/ca_certificate.pem&certfile=spec/tls/client_certificate.pem&keyfile=spec/tls/client_key.pem" }

            it "parses tls options" do
              expect(subject[:verify]).to be_falsey
              expect(subject[:fail_if_no_peer_cert]).to be_falsey
              expect(subject[:cacertfile]).to eq("spec/tls/ca_certificate.pem")
              expect(subject[:certfile]).to eq("spec/tls/client_certificate.pem")
              expect(subject[:keyfile]).to eq("spec/tls/client_key.pem")
            end
          end

          context "absent" do
          let(:uri) { "amqps://rabbitmq" }

          it "falls back to default tls options" do
            expect(subject[:verify]).to be_falsey
            expect(subject[:fail_if_no_peer_cert]).to be_falsey
            expect(subject[:cacertfile]).to be_nil
            expect(subject[:certfile]).to be_nil
            expect(subject[:keyfile]).to be_nil
          end
        end
        end
      end
    end
  end
end
