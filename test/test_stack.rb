require 'minitest_helper'
require 'diameter/stack'
require 'mocha/mini_test'

describe 'Stack', 'A client DiameterStack' do

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

  it 'moves into UP when a successful CEA is received' do
    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
      
    avps = [AVP.create('Origin-Host', 'bob'),
           AVP.create('Acct-Application-Id', @acct_app_id_1)]
    cea = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: false, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire

    @s.handle_message(cea, @socket_id)
      
    @s.peer_state('bob').must_equal :UP
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

  it "doesn't move into UP when a CEA from an unknown host is received" do
    socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'eve'),
           AVP.create('Acct-Application-Id', @acct_app_id_1)]
    cea = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: false, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire

    @s.handle_message(cea, socket_id)

    @s.peer_state('bob').must_equal :WAITING
  end

  it 'wait_for_state_change triggers when a successful CEA is received' do
    socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    peer = @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'bob'),
           AVP.create('Acct-Application-Id', @acct_app_id_1)]
    cea = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: false, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire

    state_has_changed_q = Queue.new

    Thread.new do
      peer.wait_for_state_change :UP
      state_has_changed_q.push 1
    end

    @s.peer_state('bob').must_equal :WAITING

    @s.handle_message(cea, socket_id)

    state_has_changed_q.pop.must_equal 1
  end

end

describe 'Stack 2', "A client DiameterStack with an established connection to 'bob'" do

  before do
    @s = Stack.new("testhost", "testrealm")
    @bob_socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(@bob_socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'bob')]
    cea = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: false, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire
    @s.handle_message(cea, @bob_socket_id)

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
    mar = @s.new_request(303, app_id: 0, proxyable: false, retransmitted: false, error: false, avps: avps)

    TCPStackHelper.any_instance.expects(:send).never
    @s.send_message(mar)
  end

  it "can't send to a peer that's not fully up" do
    avps = [AVP.create('Destination-Host', 'eve')]
    mar = @s.new_request(303, app_id: 0, proxyable: false, retransmitted: false, error: false, avps: avps)

    @s.connect_to_peer('aaa://localhost', 'eve', 'eve-realm')
    @s.peer_state('eve').must_equal :WAITING
    TCPStackHelper.any_instance.expects(:send).never
    @s.send_message(mar)
  end

  it 'fulfils the promise when an answer is delivered' do
    avps = [AVP.create('Destination-Host', 'bob')]
    mar = @s.new_request(303, app_id: 0, proxyable: false, retransmitted: false, error: false, avps: avps)

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

    dwr = DiameterMessage.new(version: 1,
                              command_code: 280,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 0,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire

    TCPStackHelper.any_instance.expects(:send)
      .with do |dwa_bytes, cxn|
      dwa = DiameterMessage.from_bytes dwa_bytes
      dwa.command_code.must_equal 280
      dwa.avp_by_name("Result-Code").uint32.must_equal 2001
      end
      .returns(nil)

    @s.handle_message(dwr, nil)

    @s.peer_state('bob').must_equal :UP
  end
end

describe 'Stack', 'A server DiameterStack' do

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
                        AVP.create("Auth-Application-Id", @vendor_auth_app_id)]),]
    cer = DiameterMessage.new(version: 1,
                              command_code: 257,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 0,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire
    @s.handle_message(cer, nil)

    @s.peer_state('bob').must_equal :UP
  end

  it 'responds with a CEA when a CER is received' do
    @s.peer_state('bob').must_equal :CLOSED

    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", @vendor_1),
                        AVP.create("Auth-Application-Id", @vendor_auth_app_id)]),]

    cer = DiameterMessage.new(version: 1,
                              command_code: 257,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 0,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire

    TCPStackHelper.any_instance.expects(:send)
      .with do |cea_bytes, cxn|
      cea = DiameterMessage.from_bytes cea_bytes
      cea.command_code.must_equal 257
      cea.avp_by_name("Result-Code").uint32.must_equal 2001
      end
      .returns(nil)

    @s.handle_message(cer, nil)

    @s.peer_state('bob').must_equal :UP
  end

  it 'responds with an error CEA if there are no common applications' do
    @s.peer_state('bob').must_equal :CLOSED

    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create('Auth-Application-Id', @acct_app_id_1 - 6)]
    cer = DiameterMessage.new(version: 1,
                              command_code: 257,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 0,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire

    TCPStackHelper.any_instance.expects(:send)
      .with do |cea_bytes, cxn|
      cea = DiameterMessage.from_bytes cea_bytes
      cea.command_code.must_equal 257
      cea.avp_by_name("Result-Code").uint32.must_equal 5010
      end
      .returns(nil)
    TCPStackHelper.any_instance.expects(:close).with(@bob_socket_id)

    @s.handle_message(cer, @bob_socket_id)

    @s.peer_state('bob').must_equal :CLOSED
  end

  it 'moves into UP when a successful CEA is received even if not all apps are shared' do
    @s.peer_state('bob').must_equal :CLOSED

    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", @vendor_1),
                        AVP.create("Auth-Application-Id", @vendor_auth_app_id)]),
            AVP.create('Auth-Application-Id', @acct_app_id_1 - 6)]
    cer = DiameterMessage.new(version: 1,
                              command_code: 257,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 0,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire
    @s.handle_message(cer, nil)

    @s.peer_state('bob').must_equal :UP
  end

  it 'ignores Vendor-ID when comparing applications' do
    @s.peer_state('bob').must_equal :CLOSED

    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create('Auth-Application-Id', @vendor_auth_app_id)]
    cer = DiameterMessage.new(version: 1,
                              command_code: 257,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 0,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire
    @s.handle_message(cer, nil)

    @s.peer_state('bob').must_equal :UP
  end
  

  it 'invokes handlers on receipt of a message' do
    handler_invoked = false
    @s.add_handler(16777216, auth: true, vendor: 10415) { handler_invoked = true }
    
    avps = [AVP.create('Origin-Host', 'bob'),
            AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", 10415),
                        AVP.create("Auth-Application-Id", 16777216)])]

    cer = DiameterMessage.new(version: 1,
                              command_code: 257,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 0,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire

    TCPStackHelper.any_instance.expects(:send)
      .returns(nil)

    @s.handle_message(cer, nil)

    @s.peer_state('bob').must_equal :UP

    avps = [AVP.create("Vendor-Specific-Application-Id",
                   [AVP.create("Vendor-Id", 10415),
                    AVP.create("Auth-Application-Id", 16777216)]),
            AVP.create('Origin-Host', 'bob'),
            AVP.create("Destination-Host", "rkd2.local"),
            AVP.create("Destination-Realm", "my-realm"),
           ]

    mar = DiameterMessage.new(version: 1,
                              command_code: 1000,
                              hbh: 1,
                              ete: 1,
                              request: true,
                              app_id: 16777216,
                              proxyable: false,
                              retransmitted: false,
                              error: false,
                              avps: avps).to_wire

    @s.handle_message(mar, nil)

    handler_invoked.must_equal true
  end

end
