require 'minitest_helper'
require 'diameter/stack'
require 'mocha/mini_test'

include Diameter

def make_cea(avps)
  Message.new(command_code: 257, hbh: 1, ete: 1,
              app_id: 0, proxyable: false,
              request: false, avps: avps).to_wire
end

describe 'A client DiameterStack' do

  before do

    # Arbitrary set of application and vendor IDs
    @auth_app_id = 166578
    @acct_app_id_1 = 6767673
    @acct_app_id_2 = 76654
    @vendor_auth_app_id = 44656
    @vendor_acct_app_id = 6686554

    @vendor_1 = 56657
    @vendor_2 = 65543

    #  Create a stack with no-op handlers for those apps
    @s = Stack.new("testhost", "testrealm")
    @s.add_handler(@auth_app_id, auth: true) { nil }
    @s.add_handler(@acct_app_id_1, acct: true) { nil }
    @s.add_handler(@acct_app_id_2, acct: true) { nil }
    @s.add_handler(@vendor_auth_app_id, auth: true, vendor: @vendor_1) { nil }
    @s.add_handler(@vendor_acct_app_id, acct: true, vendor: @vendor_2) { nil }

    @socket_id = 1004

    # Mock out the real-world TCP interactions
    Internals::TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(@socket_id)

    # Basic sanity check on every message sent - does it have the
    # "version 1" Diameter first header byte?
    Internals::TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)
  end

  after do
    @s.shutdown
  end

  it 'moves into WAITING on initial connection' do
    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
    @s.peer_state('bob').must_equal :WAITING
  end

  it 'sends a CER with all its application ids on initial connection' do
    Internals::TCPStackHelper.any_instance.stubs(:send).with do
      |cer_bytes, _c|
      cer = Message.from_bytes cer_bytes
      cer.avp_by_name("Auth-Application-Id").uint32.must_equal @auth_app_id
      cer.all_avps_by_name("Acct-Application-Id").collect(&:uint32).must_equal [@acct_app_id_1, @acct_app_id_2]
    end
      .returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
  end

  it 'sends a CER to the top peer when connecting to a realm' do
    primary_host = "peer1.bob-realm"
    primary_port = 5676

    host2 = "peer2.bob-realm"
    host3 = "peer3.bob-realm"
    host4 = "peer4.bob-realm"
    
    # Mock out the real-world TCP interactions
    Internals::TCPStackHelper.any_instance.expects(:setup_new_connection).with(primary_host, primary_port).returns(@socket_id)

    fake_answer = Dnsruby::Message.new
    fake_answer.add_answer(Dnsruby::RR.create(type: "SRV", name: "_diameter._tcp.bob-realm", target: host2, port: primary_port, priority: 2, weight: 50))
    fake_answer.add_answer(Dnsruby::RR.create(type: "SRV", name: "_diameter._tcp.bob-realm", target: primary_host, port: primary_port, priority: 1, weight: 100))
    fake_answer.add_answer(Dnsruby::RR.create(type: "SRV", name: "_diameter._tcp.bob-realm", target: host3, port: primary_port, priority: 2, weight: 100))
    fake_answer.add_answer(Dnsruby::RR.create(type: "SRV", name: "_diameter._tcp.bob-realm", target: host4, port: primary_port, priority: 4, weight: 100))
    
    Dnsruby::Resolver.any_instance.stubs(:query).with("_diameter._tcp.bob-realm", "SRV").returns(fake_answer)
    @s.connect_to_realm('bob-realm')

    @s.peer_state('peer1.bob-realm').must_equal :WAITING
    @s.peer_state('peer2.bob-realm').must_equal :CLOSED
    @s.peer_state('peer3.bob-realm').must_equal :CLOSED
    @s.peer_state('peer4.bob-realm').must_equal :CLOSED
  end

  it 'moves into UP when a successful CEA is received' do
    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
      
    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create('Acct-Application-Id', @acct_app_id_1)]

    @s.handle_message(make_cea(avps), @socket_id)
      
    @s.peer_state('bob').must_equal :UP
  end

  it "moves into UP and learns the Destination-Host on the CEA" do
    peer = @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'eve'),
            AVP.create('Acct-Application-Id', @acct_app_id_1)]

    @s.handle_message(make_cea(avps), @socket_id)

    peer.identity.must_equal 'eve'
    peer.state.must_equal :UP
  end

  it 'wait_for_state_change triggers when a successful CEA is received' do
    peer = @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    state_has_changed_q = Queue.new

    Thread.new do
      peer.wait_for_state_change :UP
      state_has_changed_q.push 1
    end

    @s.peer_state('bob').must_equal :WAITING

    avps = [AVP.create('Origin-Host', 'bob'),
           AVP.create('Acct-Application-Id', @acct_app_id_1)]
    @s.handle_message(make_cea(avps), @socket_id)

    state_has_changed_q.pop.must_equal 1
  end

end

describe "A client DiameterStack with an established connection to 'bob'" do

  before do
    @s = Stack.new("testhost", "testrealm", timeout: 0.1)
    @bob_socket_id = 1004

    Internals::TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(@bob_socket_id)
    Internals::TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'bob')]
    @s.handle_message(make_cea(avps), @bob_socket_id)

    @s.peer_state('bob').must_equal :UP
  end

  after do
    @s.shutdown
  end

  it 'routes subsequent messages on Destination-Host' do
    avps = [AVP.create('Destination-Host', 'bob')]
    mar = Message.new(command_code: 307, app_id: 0, avps: avps)

    Internals::TCPStackHelper.any_instance.expects(:send)
      .with { |x,c| c == @bob_socket_id && x == mar.to_wire }
      .returns(nil)
    @s.send_request(mar)

  end

  it 'routes subsequent messages on Destination-Realm' do
    avps = [AVP.create('Destination-Realm', 'bob-realm')]
    mar = Message.new(command_code: 307, app_id: 0, avps: avps)

    Internals::TCPStackHelper.any_instance.expects(:send)
      .with { |x,c| c == @bob_socket_id && x == mar.to_wire }
      .returns(nil)
    @s.send_request(mar)
  end

  it "can't route to an unknown Destination-Realm" do
    avps = [AVP.create('Destination-Realm', 'eve-realm')]
    mar = Message.new(command_code: 307, app_id: 0, avps: avps)

    proc { @s.send_request(mar) }.must_raise RuntimeError
  end

  it "can't route a request with no routing AVPs" do
    mar = Message.new(command_code: 307, app_id: 0, avps: [])

    proc { @s.send_request(mar) }.must_raise RuntimeError
  end

  it "can't send to a peer it isn't connected to" do
    avps = [AVP.create('Destination-Host', 'eve')]
    mar = Message.new(command_code: 305, app_id: 0, avps: avps)

    Internals::TCPStackHelper.any_instance.expects(:send).never
    proc { @s.send_request(mar) }.must_raise RuntimeError
  end

  it "can't send to a peer that's not fully up" do
    avps = [AVP.create('Destination-Host', 'eve')]
    mar = Message.new(command_code: 306, app_id: 0, avps: avps)

    @s.connect_to_peer('aaa://localhost', 'eve', 'eve-realm')
    @s.peer_state('eve').must_equal :WAITING
    Internals::TCPStackHelper.any_instance.expects(:send).never
    @s.send_request(mar)
  end

  it 'fulfils the promise when an answer is delivered' do
    avps = [AVP.create('Destination-Host', 'bob')]
    mar = Message.new(command_code: 304, app_id: 0, avps: avps)

    Internals::TCPStackHelper.any_instance.expects(:send)
      .with { |x,c| c == @bob_socket_id && x == mar.to_wire }
      .returns(nil)

    promised_maa = @s.send_request(mar)
    promised_maa.state.must_equal :pending

    maa = mar.create_answer(2001, avps: [AVP.create('Origin-Host', 'bob')])
    @s.handle_message(maa.to_wire, @bob_socket_id)

    promised_maa.wait
    promised_maa.state.must_equal :fulfilled
  end

  it 'times out an unanswered request' do
    avps = [AVP.create('Destination-Host', 'bob')]
    mar = Message.new(command_code: 304, app_id: 0, avps: avps)

    Internals::TCPStackHelper.any_instance.expects(:send)
      .with { |x,c| c == @bob_socket_id && x == mar.to_wire }
      .returns(nil)

    promised_maa = @s.send_request(mar)

=begin
    promised_maa.wait
    promised_maa.value.must_equal :timeout
=end
  end

  it 'adds the Origin-Host and Origin-Realm AVPs to answers' do
    avps = [AVP.create('User-Name', 'shibboleth')]
    maa = Message.new(command_code: 304, request: false, app_id: 0, avps: avps)

    Internals::TCPStackHelper.any_instance.expects(:send)
      .with do |x,c|
      c.must_equal @bob_socket_id
      maa2 = Message.from_bytes(x)
      maa2['User-Name'].octet_string.must_equal 'shibboleth'
      maa2['Origin-Host'].octet_string.must_equal 'testhost'
      maa2['Origin-Realm'].octet_string.must_equal 'testrealm'
    end
      .returns(nil)

    @s.send_answer(maa, @bob_socket_id)
  end

  it 'doesn\'t overwrite existing Origin-Host and Origin-Realm AVPs on answers' do
    avps = [AVP.create('User-Name', 'shibboleth'),
            AVP.create('Origin-Host', 'abcd'),
            AVP.create('Origin-Realm', 'efgh'),
           ]
    maa = Message.new(command_code: 304, request: false, app_id: 0, avps: avps)

    Internals::TCPStackHelper.any_instance.expects(:send)
      .with do |x,c|
      c.must_equal @bob_socket_id
      maa2 = Message.from_bytes(x)
      maa2['User-Name'].octet_string.must_equal 'shibboleth'
      maa2['Origin-Host'].octet_string.must_equal 'abcd'
      maa2['Origin-Realm'].octet_string.must_equal 'efgh'
      maa2.avps('Origin-Host').length.must_equal 1
      maa2.avps('Origin-Realm').length.must_equal 1
    end
      .returns(nil)

    @s.send_answer(maa, @bob_socket_id)
  end

  it 'responds with a DWA when a DWR is received' do
    avps = [AVP.create('Origin-Host', 'bob')]

    dwr = Message.new(command_code: 280,
                      hbh: 1,
                      ete: 1,
                      app_id: 0,
                      proxyable: false,
                      avps: avps).to_wire

    Internals::TCPStackHelper.any_instance.expects(:send).with do |dwa_bytes, cxn|
      dwa = Message.from_bytes dwa_bytes
      dwa.command_code.must_equal 280
      dwa.avp_by_name("Result-Code").uint32.must_equal 2001
    end
      .returns(nil)

    @s.handle_message(dwr, nil)
    @s.peer_state('bob').must_equal :UP
  end
end
