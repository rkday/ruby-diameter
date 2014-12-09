require 'minitest_helper'
require 'diameter/stack'
require 'mocha/mini_test'

def make_cea(avps)
  DiameterMessage.new(command_code: 257, hbh: 1, ete: 1,
                            app_id: 0, proxyable: false,
                            request: false, avps: avps).to_wire
end

def make_cer(avps)
  DiameterMessage.new(command_code: 257, hbh: 1, ete: 1,
                      app_id: 0, proxyable: false,
                      avps: avps).to_wire
end
  

describe 'A client DiameterStack' do

  before do
    # Mock out the interactions with the real world
    @auth_app_id = 166578
    @acct_app_id_1 = 6767673
    @acct_app_id_2 = 76654
    @vendor_auth_app_id = 44656
    @vendor_acct_app_id = 6686554

    @vendor_1 = 56657
    @vendor_2 = 65543
    
    @s = Stack.new("testhost", "testrealm")
    @s.add_handler(@auth_app_id, auth: true) { nil }
    @s.add_handler(@acct_app_id_1, acct: true) { nil }
    @s.add_handler(@acct_app_id_2, acct: true) { nil }
    @s.add_handler(@vendor_auth_app_id, auth: true, vendor: @vendor_1) { nil }
    @s.add_handler(@vendor_acct_app_id, acct: true, vendor: @vendor_2) { nil }

    @socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(@socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)
  end

  it 'moves into WAITING on initial connection' do
    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
    @s.peer_state('bob').must_equal :WAITING
  end

  it 'sends a CER with all its application ids on initial connection' do
    TCPStackHelper.any_instance.stubs(:send).with do
      |cer_bytes, _c|
      cer = DiameterMessage.from_bytes cer_bytes
      cer.avp_by_name("Auth-Application-Id").uint32.must_equal @auth_app_id
      cer.all_avps_by_name("Acct-Application-Id").collect(&:uint32).must_equal [@acct_app_id_1, @acct_app_id_2]
    end
      .returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
  end

  it 'moves into UP when a successful CEA is received' do
    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
      
    avps = [AVP.create('Origin-Host', 'bob'),
           AVP.create('Acct-Application-Id', @acct_app_id_1)]

    @s.handle_message(make_cea(avps), @socket_id)
      
    @s.peer_state('bob').must_equal :UP
  end

  it "doesn't move into UP when a CEA from an unknown host is received" do
    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'eve'),
           AVP.create('Acct-Application-Id', @acct_app_id_1)]

    @s.handle_message(make_cea(avps), @socket_id)

    @s.peer_state('bob').must_equal :WAITING
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
    @s = Stack.new("testhost", "testrealm")
    @bob_socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(@bob_socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'bob')]
    @s.handle_message(make_cea(avps), @socket_id)

    @s.peer_state('bob').must_equal :UP
  end

  it 'routes subsequent messages on Destination-Host' do
    avps = [AVP.create('Destination-Host', 'bob')]
    mar = @s.new_request(303, app_id: 0, proxyable: false, retransmitted: false, error: false, avps: avps)

    TCPStackHelper.any_instance.expects(:send)
      .with { |x,c| c == @bob_socket_id && x == mar.to_wire }
      .returns(nil)
    @s.send_message(mar)
  end

  it "can't send to a peer it isn't connected to" do
    avps = [AVP.create('Destination-Host', 'eve')]
    mar = @s.new_request(303, app_id: 0, avps: avps)

    TCPStackHelper.any_instance.expects(:send).never
    @s.send_message(mar)
  end

  it "can't send to a peer that's not fully up" do
    avps = [AVP.create('Destination-Host', 'eve')]
    mar = @s.new_request(303, app_id: 0, avps: avps)

    @s.connect_to_peer('aaa://localhost', 'eve', 'eve-realm')
    @s.peer_state('eve').must_equal :WAITING
    TCPStackHelper.any_instance.expects(:send).never
    @s.send_message(mar)
  end

  it 'fulfils the promise when an answer is delivered' do
    avps = [AVP.create('Destination-Host', 'bob')]
    mar = @s.new_request(303, app_id: 0, avps: avps)

    TCPStackHelper.any_instance.expects(:send)
      .with { |x,c| c == @bob_socket_id && x == mar.to_wire }
      .returns(nil)

    promised_maa = @s.send_message(mar)
    promised_maa.state.must_equal :pending

    maa = mar.create_answer
    maa.avps = [AVP.create('Origin-Host', 'bob')]
    @s.handle_message(maa.to_wire, @bob_socket_id)

    promised_maa.wait
    promised_maa.state.must_equal :fulfilled
  end

  it 'responds with a DWA when a DWR is received' do
    avps = [AVP.create('Origin-Host', 'bob')]

    dwr = DiameterMessage.new(command_code: 280,
                              hbh: 1,
                              ete: 1,
                              app_id: 0,
                              proxyable: false,
                              avps: avps).to_wire

    TCPStackHelper.any_instance.expects(:send).with do |dwa_bytes, cxn|
      dwa = DiameterMessage.from_bytes dwa_bytes
      dwa.command_code.must_equal 280
      dwa.avp_by_name("Result-Code").uint32.must_equal 2001
    end
      .returns(nil)

    @s.handle_message(dwr, nil)
    @s.peer_state('bob').must_equal :UP
  end
end

describe 'A server DiameterStack' do

  before do
    # Mock out the interactions with the real world
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)
    TCPStackHelper.any_instance.stubs(:start_main_loop).returns(nil)

    @bob_socket_id = 1005
    
    @auth_app_id = 166578
    @acct_app_id_1 = 6767673
    @acct_app_id_2 = 76654
    @vendor_auth_app_id = 44656
    @vendor_acct_app_id = 6686554

    @vendor_1 = 56657
    @vendor_2 = 65543
    
    @s = Stack.new("testhost", "testrealm")
    @s.add_handler(@auth_app_id, auth: true) { nil }
    @s.add_handler(@acct_app_id_1, acct: true) { nil }
    @s.add_handler(@acct_app_id_2, acct: true) { nil }
    @s.add_handler(@vendor_auth_app_id, auth: true, vendor: @vendor_1) { nil }
    @s.add_handler(@vendor_acct_app_id, acct: true, vendor: @vendor_2) { nil }
    @s.start
  end

  it 'moves the peer from CLOSED into UP when a CER is received' do
    @s.peer_state('bob').must_equal :CLOSED

    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", @vendor_1),
                        AVP.create("Auth-Application-Id", @vendor_auth_app_id)])]

    @s.handle_message(make_cer(avps), nil)

    @s.peer_state('bob').must_equal :UP
  end

  it 'responds with a CEA when a CER is received' do
    @s.peer_state('bob').must_equal :CLOSED

    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", @vendor_1),
                        AVP.create("Auth-Application-Id", @vendor_auth_app_id)]),]

    TCPStackHelper.any_instance.expects(:send)
      .with do |cea_bytes, cxn|
      cea = DiameterMessage.from_bytes cea_bytes
      cea.command_code.must_equal 257
      cea.avp_by_name("Result-Code").uint32.must_equal 2001
      end
      .returns(nil)

    @s.handle_message(make_cer(avps), nil)

    @s.peer_state('bob').must_equal :UP
  end

  context "correct application ID handling" do
  
    it 'responds with an error CEA if there are no common applications' do
      @s.peer_state('bob').must_equal :CLOSED

      avps = [AVP.create('Origin-Host', 'bob'),
              AVP.create('Auth-Application-Id', @acct_app_id_1 - 6)]

      TCPStackHelper.any_instance.expects(:send)
        .with do |cea_bytes, cxn|
        cea = DiameterMessage.from_bytes cea_bytes
        cea.command_code.must_equal 257
        cea.avp_by_name("Result-Code").uint32.must_equal 5010
      end
        .returns(nil)
      TCPStackHelper.any_instance.expects(:close).with(@bob_socket_id)

      @s.handle_message(make_cer(avps), @bob_socket_id)

      @s.peer_state('bob').must_equal :CLOSED
    end

    it 'moves into UP when a successful CEA is received even if not all apps are shared' do
      @s.peer_state('bob').must_equal :CLOSED

      avps = [AVP.create('Origin-Host', 'bob'),
              AVP.create("Vendor-Specific-Application-Id",
                         [AVP.create("Vendor-Id", @vendor_1),
                          AVP.create("Auth-Application-Id", @vendor_auth_app_id)]),
              AVP.create('Auth-Application-Id', @acct_app_id_1 - 6)]

      @s.handle_message(make_cer(avps), nil)

      @s.peer_state('bob').must_equal :UP
    end

    it 'ignores Vendor-ID when comparing applications' do
      @s.peer_state('bob').must_equal :CLOSED

      avps = [AVP.create('Origin-Host', 'bob'),
              AVP.create('Auth-Application-Id', @vendor_auth_app_id)]
      
      @s.handle_message(make_cer(avps), nil)
      @s.peer_state('bob').must_equal :UP
    end
  end
end

describe 'A server DiameterStack with an existing connection' do
  before do
    # Mock out the interactions with the real world
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)
    TCPStackHelper.any_instance.stubs(:start_main_loop).returns(nil)

    @bob_socket_id = 1005    
    @auth_app_id = 166578
    
    @s = Stack.new("testhost", "testrealm")
    @s.add_handler(@auth_app_id, auth: true) { nil }
    @s.start

    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create('Auth-Application-Id', @auth_app_id)]
    @s.handle_message(make_cer(avps), @bob_socket_id)

    @s.peer_state('bob').must_equal :UP
  end

  it 'invokes handlers on receipt of a message' do
    handler_invoked = false

    # Change the handler
    @s.add_handler(@auth_app_id, auth: true) { handler_invoked = true }
    
    avps = [AVP.create("Auth-Application-Id", @auth_app_id),
            AVP.create('Origin-Host', 'bob'),
            AVP.create("Destination-Host", "rkd2.local"),
            AVP.create("Destination-Realm", "my-realm")]

    msg = DiameterMessage.new(command_code: 1000, hbh: 1, ete: 1,
                              app_id: @auth_app_id, avps: avps).to_wire

    @s.handle_message(msg, nil)

    handler_invoked.must_equal true
  end
end
