module AMQ
  RSpec.describe Protocol do
    it "should have PROTOCOL_VERSION constant" do
      expect(Protocol::PROTOCOL_VERSION).to match(/^\d+\.\d+\.\d$/)
    end

    it "should have DEFAULT_PORT constant" do
      expect(Protocol::DEFAULT_PORT).to be_kind_of(Integer)
    end

    it "should have PREAMBLE constant" do
      expect(Protocol::PREAMBLE).to be_kind_of(String)
    end

    describe Protocol::Error do
      it "should be an exception class" do
        expect(Protocol::Error.ancestors).to include(Exception)
      end
    end

    describe Protocol::Connection do
      it "should be a subclass of Class" do
        expect(Protocol::Connection.superclass).to eq(Protocol::Class)
      end

      it "should have name equal to connection" do
        expect(Protocol::Connection.name).to eql("connection")
      end

      it "should have method id equal to 10" do
        expect(Protocol::Connection.method_id).to eq(10)
      end

      describe Protocol::Connection::Start do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::Start.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.start" do
          expect(Protocol::Connection::Start.name).to eql("connection.start")
        end

        it "should have method id equal to 10" do
          expect(Protocol::Connection::Start.method_id).to eq(10)
        end
      end

      describe Protocol::Connection::StartOk do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::StartOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.start-ok" do
          expect(Protocol::Connection::StartOk.name).to eql("connection.start-ok")
        end

        it "has method id equal to 11" do
          expect(Protocol::Connection::StartOk.method_id).to eq(11)
        end
      end

      describe Protocol::Connection::Secure do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::Secure.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.secure" do
          expect(Protocol::Connection::Secure.name).to eql("connection.secure")
        end

        it "has method id equal to 20" do
          expect(Protocol::Connection::Secure.method_id).to eq(20)
        end
      end

      describe Protocol::Connection::SecureOk do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::SecureOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.secure-ok" do
          expect(Protocol::Connection::SecureOk.name).to eql("connection.secure-ok")
        end

        it "has method id equal to 21" do
          expect(Protocol::Connection::SecureOk.method_id).to eq(21)
        end
      end

      describe Protocol::Connection::Tune do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::Tune.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.tune" do
          expect(Protocol::Connection::Tune.name).to eql("connection.tune")
        end

        it "has method id equal to 30" do
          expect(Protocol::Connection::Tune.method_id).to eq(30)
        end
      end

      describe Protocol::Connection::TuneOk do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::TuneOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.tune-ok" do
          expect(Protocol::Connection::TuneOk.name).to eql("connection.tune-ok")
        end

        it "has method id equal to 31" do
          expect(Protocol::Connection::TuneOk.method_id).to eq(31)
        end

        describe ".encode" do
          it do
            frame = Protocol::Connection::TuneOk.encode(0, 131072, 0)
            expect(frame.payload).to eql("\x00\n\x00\x1F\x00\x00\x00\x02\x00\x00\x00\x00")
          end
        end
      end

      describe Protocol::Connection::Open do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::Open.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.open" do
          expect(Protocol::Connection::Open.name).to eql("connection.open")
        end

        it "has method id equal to 40" do
          expect(Protocol::Connection::Open.method_id).to eq(40)
        end
      end

      describe Protocol::Connection::OpenOk do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::OpenOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.open-ok" do
          expect(Protocol::Connection::OpenOk.name).to eql("connection.open-ok")
        end

        it "has method id equal to 41" do
          expect(Protocol::Connection::OpenOk.method_id).to eq(41)
        end
      end

      describe Protocol::Connection::Close do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::Close.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.close" do
          expect(Protocol::Connection::Close.name).to eql("connection.close")
        end

        it "has method id equal to 50" do
          expect(Protocol::Connection::Close.method_id).to eq(50)
        end
      end

      describe Protocol::Connection::CloseOk do
        it "should be a subclass of Method" do
          expect(Protocol::Connection::CloseOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to connection.close-ok" do
          expect(Protocol::Connection::CloseOk.name).to eql("connection.close-ok")
        end

        it "has method id equal to 51" do
          expect(Protocol::Connection::CloseOk.method_id).to eq(51)
        end
      end
    end

    describe Protocol::Channel do
      it "should be a subclass of Class" do
        expect(Protocol::Channel.superclass).to eq(Protocol::Class)
      end

      it "should have name equal to channel" do
        expect(Protocol::Channel.name).to eql("channel")
      end

      it "has method id equal to 20" do
        expect(Protocol::Channel.method_id).to eq(20)
      end

      describe Protocol::Channel::Open do
        it "should be a subclass of Method" do
          expect(Protocol::Channel::Open.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to channel.open" do
          expect(Protocol::Channel::Open.name).to eql("channel.open")
        end

        it "has method id equal to 10" do
          expect(Protocol::Channel::Open.method_id).to eq(10)
        end
      end

      describe Protocol::Channel::OpenOk do
        it "should be a subclass of Method" do
          expect(Protocol::Channel::OpenOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to channel.open-ok" do
          expect(Protocol::Channel::OpenOk.name).to eql("channel.open-ok")
        end

        it "has method id equal to 11" do
          expect(Protocol::Channel::OpenOk.method_id).to eq(11)
        end
      end

      describe Protocol::Channel::Flow do
        it "should be a subclass of Method" do
          expect(Protocol::Channel::Flow.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to channel.flow" do
          expect(Protocol::Channel::Flow.name).to eql("channel.flow")
        end

        it "has method id equal to 20" do
          expect(Protocol::Channel::Flow.method_id).to eq(20)
        end
      end

      describe Protocol::Channel::FlowOk do
        it "should be a subclass of Method" do
          expect(Protocol::Channel::FlowOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to channel.flow-ok" do
          expect(Protocol::Channel::FlowOk.name).to eql("channel.flow-ok")
        end

        it "has method id equal to 21" do
          expect(Protocol::Channel::FlowOk.method_id).to eq(21)
        end
      end

      describe Protocol::Channel::Close do
        it "should be a subclass of Method" do
          expect(Protocol::Channel::Close.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to channel.close" do
          expect(Protocol::Channel::Close.name).to eql("channel.close")
        end

        it "has method id equal to 40" do
          expect(Protocol::Channel::Close.method_id).to eq(40)
        end
      end

      describe Protocol::Channel::CloseOk do
        it "should be a subclass of Method" do
          expect(Protocol::Channel::CloseOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to channel.close-ok" do
          expect(Protocol::Channel::CloseOk.name).to eql("channel.close-ok")
        end

        it "has method id equal to 41" do
          expect(Protocol::Channel::CloseOk.method_id).to eq(41)
        end
      end
    end

    describe Protocol::Exchange do
      it "should be a subclass of Class" do
        expect(Protocol::Exchange.superclass).to eq(Protocol::Class)
      end

      it "should have name equal to exchange" do
        expect(Protocol::Exchange.name).to eql("exchange")
      end

      it "has method id equal to 40" do
        expect(Protocol::Exchange.method_id).to eq(40)
      end

      describe Protocol::Exchange::Declare do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::Declare.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.declare" do
          expect(Protocol::Exchange::Declare.name).to eql("exchange.declare")
        end

        it "has method id equal to 10" do
          expect(Protocol::Exchange::Declare.method_id).to eq(10)
        end
      end

      describe Protocol::Exchange::DeclareOk do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::DeclareOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.declare-ok" do
          expect(Protocol::Exchange::DeclareOk.name).to eql("exchange.declare-ok")
        end

        it "has method id equal to 11" do
          expect(Protocol::Exchange::DeclareOk.method_id).to eq(11)
        end
      end

      describe Protocol::Exchange::Delete do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::Delete.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.delete" do
          expect(Protocol::Exchange::Delete.name).to eql("exchange.delete")
        end

        it "has method id equal to 20" do
          expect(Protocol::Exchange::Delete.method_id).to eq(20)
        end
      end

      describe Protocol::Exchange::DeleteOk do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::DeleteOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.delete-ok" do
          expect(Protocol::Exchange::DeleteOk.name).to eql("exchange.delete-ok")
        end

        it "has method id equal to 21" do
          expect(Protocol::Exchange::DeleteOk.method_id).to eq(21)
        end
      end

      describe Protocol::Exchange::Bind do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::Bind.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.bind" do
          expect(Protocol::Exchange::Bind.name).to eql("exchange.bind")
        end

        it "has method id equal to 30" do
          expect(Protocol::Exchange::Bind.method_id).to eq(30)
        end
      end

      describe Protocol::Exchange::BindOk do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::BindOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.bind-ok" do
          expect(Protocol::Exchange::BindOk.name).to eql("exchange.bind-ok")
        end

        it "has method id equal to 31" do
          expect(Protocol::Exchange::BindOk.method_id).to eq(31)
        end
      end

      describe Protocol::Exchange::Unbind do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::Unbind.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.unbind" do
          expect(Protocol::Exchange::Unbind.name).to eql("exchange.unbind")
        end

        it "has method id equal to 40" do
          expect(Protocol::Exchange::Unbind.method_id).to eq(40)
        end
      end

      describe Protocol::Exchange::UnbindOk do
        it "should be a subclass of Method" do
          expect(Protocol::Exchange::UnbindOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to exchange.unbind-ok" do
          expect(Protocol::Exchange::UnbindOk.name).to eql("exchange.unbind-ok")
        end

        it "has method id equal to 51" do
          expect(Protocol::Exchange::UnbindOk.method_id).to eq(51)
        end
      end
    end

    describe Protocol::Queue do
      it "should be a subclass of Class" do
        expect(Protocol::Queue.superclass).to eq(Protocol::Class)
      end

      it "should have name equal to queue" do
        expect(Protocol::Queue.name).to eql("queue")
      end

      it "has method id equal to 50" do
        expect(Protocol::Queue.method_id).to eq(50)
      end

      describe Protocol::Queue::Declare do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::Declare.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.declare" do
          expect(Protocol::Queue::Declare.name).to eql("queue.declare")
        end

        it "has method id equal to 10" do
          expect(Protocol::Queue::Declare.method_id).to eq(10)
        end
      end

      describe Protocol::Queue::DeclareOk do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::DeclareOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.declare-ok" do
          expect(Protocol::Queue::DeclareOk.name).to eql("queue.declare-ok")
        end

        it "has method id equal to 11" do
          expect(Protocol::Queue::DeclareOk.method_id).to eq(11)
        end
      end

      describe Protocol::Queue::Bind do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::Bind.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.bind" do
          expect(Protocol::Queue::Bind.name).to eql("queue.bind")
        end

        it "has method id equal to 20" do
          expect(Protocol::Queue::Bind.method_id).to eq(20)
        end
      end

      describe Protocol::Queue::BindOk do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::BindOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.bind-ok" do
          expect(Protocol::Queue::BindOk.name).to eql("queue.bind-ok")
        end

        it "has method id equal to 21" do
          expect(Protocol::Queue::BindOk.method_id).to eq(21)
        end
      end

      describe Protocol::Queue::Purge do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::Purge.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.purge" do
          expect(Protocol::Queue::Purge.name).to eql("queue.purge")
        end

        it "has method id equal to 30" do
          expect(Protocol::Queue::Purge.method_id).to eq(30)
        end
      end

      describe Protocol::Queue::PurgeOk do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::PurgeOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.purge-ok" do
          expect(Protocol::Queue::PurgeOk.name).to eql("queue.purge-ok")
        end

        it "has method id equal to 31" do
          expect(Protocol::Queue::PurgeOk.method_id).to eq(31)
        end
      end

      describe Protocol::Queue::Delete do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::Delete.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.delete" do
          expect(Protocol::Queue::Delete.name).to eql("queue.delete")
        end

        it "has method id equal to 40" do
          expect(Protocol::Queue::Delete.method_id).to eq(40)
        end
      end

      describe Protocol::Queue::DeleteOk do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::DeleteOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.delete-ok" do
          expect(Protocol::Queue::DeleteOk.name).to eql("queue.delete-ok")
        end

        it "has method id equal to 41" do
          expect(Protocol::Queue::DeleteOk.method_id).to eq(41)
        end
      end

      describe Protocol::Queue::Unbind do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::Unbind.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.unbind" do
          expect(Protocol::Queue::Unbind.name).to eql("queue.unbind")
        end

        it "has method id equal to 50" do
          expect(Protocol::Queue::Unbind.method_id).to eq(50)
        end
      end

      describe Protocol::Queue::UnbindOk do
        it "should be a subclass of Method" do
          expect(Protocol::Queue::UnbindOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to queue.unbind-ok" do
          expect(Protocol::Queue::UnbindOk.name).to eql("queue.unbind-ok")
        end

        it "has method id equal to 51" do
          expect(Protocol::Queue::UnbindOk.method_id).to eq(51)
        end
      end
    end

    describe Protocol::Basic do
      it "should be a subclass of Class" do
        expect(Protocol::Basic.superclass).to eq(Protocol::Class)
      end

      it "should have name equal to basic" do
        expect(Protocol::Basic.name).to eql("basic")
      end

      it "has method id equal to 60" do
        expect(Protocol::Basic.method_id).to eq(60)
      end

      describe Protocol::Basic::Qos do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Qos.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.qos" do
          expect(Protocol::Basic::Qos.name).to eql("basic.qos")
        end

        it "has method id equal to 10" do
          expect(Protocol::Basic::Qos.method_id).to eq(10)
        end
      end

      describe Protocol::Basic::QosOk do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::QosOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.qos-ok" do
          expect(Protocol::Basic::QosOk.name).to eql("basic.qos-ok")
        end

        it "has method id equal to 11" do
          expect(Protocol::Basic::QosOk.method_id).to eq(11)
        end
      end

      describe Protocol::Basic::Consume do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Consume.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.consume" do
          expect(Protocol::Basic::Consume.name).to eql("basic.consume")
        end

        it "has method id equal to 20" do
          expect(Protocol::Basic::Consume.method_id).to eq(20)
        end
      end

      describe Protocol::Basic::ConsumeOk do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::ConsumeOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.consume-ok" do
          expect(Protocol::Basic::ConsumeOk.name).to eql("basic.consume-ok")
        end

        it "has method id equal to 21" do
          expect(Protocol::Basic::ConsumeOk.method_id).to eq(21)
        end
      end

      describe Protocol::Basic::Cancel do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Cancel.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.cancel" do
          expect(Protocol::Basic::Cancel.name).to eql("basic.cancel")
        end

        it "has method id equal to 30" do
          expect(Protocol::Basic::Cancel.method_id).to eq(30)
        end
      end

      describe Protocol::Basic::CancelOk do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::CancelOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.cancel-ok" do
          expect(Protocol::Basic::CancelOk.name).to eql("basic.cancel-ok")
        end

        it "has method id equal to 31" do
          expect(Protocol::Basic::CancelOk.method_id).to eq(31)
        end
      end

      describe Protocol::Basic::Publish do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Publish.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.publish" do
          expect(Protocol::Basic::Publish.name).to eql("basic.publish")
        end

        it "has method id equal to 40" do
          expect(Protocol::Basic::Publish.method_id).to eq(40)
        end
      end

      describe Protocol::Basic::Return do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Return.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.return" do
          expect(Protocol::Basic::Return.name).to eql("basic.return")
        end

        it "has method id equal to 50" do
          expect(Protocol::Basic::Return.method_id).to eq(50)
        end
      end

      describe Protocol::Basic::Deliver do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Deliver.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.deliver" do
          expect(Protocol::Basic::Deliver.name).to eql("basic.deliver")
        end

        it "has method id equal to 60" do
          expect(Protocol::Basic::Deliver.method_id).to eq(60)
        end
      end

      describe Protocol::Basic::Get do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Get.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.get" do
          expect(Protocol::Basic::Get.name).to eql("basic.get")
        end

        it "has method id equal to 70" do
          expect(Protocol::Basic::Get.method_id).to eq(70)
        end
      end

      describe Protocol::Basic::GetOk do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::GetOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.get-ok" do
          expect(Protocol::Basic::GetOk.name).to eql("basic.get-ok")
        end

        it "has method id equal to 71" do
          expect(Protocol::Basic::GetOk.method_id).to eq(71)
        end
      end

      describe Protocol::Basic::GetEmpty do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::GetEmpty.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.get-empty" do
          expect(Protocol::Basic::GetEmpty.name).to eql("basic.get-empty")
        end

        it "has method id equal to 72" do
          expect(Protocol::Basic::GetEmpty.method_id).to eq(72)
        end
      end

      describe Protocol::Basic::Ack do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Ack.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.ack" do
          expect(Protocol::Basic::Ack.name).to eql("basic.ack")
        end

        it "has method id equal to 80" do
          expect(Protocol::Basic::Ack.method_id).to eq(80)
        end
      end

      describe Protocol::Basic::Reject do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Reject.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.reject" do
          expect(Protocol::Basic::Reject.name).to eql("basic.reject")
        end

        it "has method id equal to 90" do
          expect(Protocol::Basic::Reject.method_id).to eq(90)
        end
      end

      describe Protocol::Basic::RecoverAsync do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::RecoverAsync.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.recover-async" do
          expect(Protocol::Basic::RecoverAsync.name).to eql("basic.recover-async")
        end

        it "has method id equal to 100" do
          expect(Protocol::Basic::RecoverAsync.method_id).to eq(100)
        end
      end

      describe Protocol::Basic::Recover do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::Recover.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.recover" do
          expect(Protocol::Basic::Recover.name).to eql("basic.recover")
        end

        it "has method id equal to 110" do
          expect(Protocol::Basic::Recover.method_id).to eq(110)
        end
      end

      describe Protocol::Basic::RecoverOk do
        it "should be a subclass of Method" do
          expect(Protocol::Basic::RecoverOk.superclass).to eq(Protocol::Method)
        end

        it "should have method name equal to basic.recover-ok" do
          expect(Protocol::Basic::RecoverOk.name).to eql("basic.recover-ok")
        end

        it "has method id equal to 111" do
          expect(Protocol::Basic::RecoverOk.method_id).to eq(111)
        end
      end
    end
  end
end
