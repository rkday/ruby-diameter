require 'minitest_helper'
require 'diameter/stack'
require 'mocha/mini_test'

include Diameter

def make_cer(avps)
  Message.new(command_code: 257, hbh: 1, ete: 1,
                      app_id: 0, proxyable: false,
                      avps: avps).to_wire
end
  


describe 'A server DiameterStack' do

  before do
    # Mock out the interactions with the real world
    Internals::TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)
    Internals::TCPStackHelper.any_instance.stubs(:start_main_loop).returns(nil)

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

  after do
    @s.shutdown
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

    Internals::TCPStackHelper.any_instance.expects(:send)
      .with do |cea_bytes, cxn|
      cea = Message.from_bytes cea_bytes
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

      Internals::TCPStackHelper.any_instance.expects(:send)
        .with do |cea_bytes, cxn|
        cea = Message.from_bytes cea_bytes
        cea.command_code.must_equal 257
        cea.avp_by_name("Result-Code").uint32.must_equal 5010
      end
        .returns(nil)
      Internals::TCPStackHelper.any_instance.expects(:close).with(@bob_socket_id)

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
    Internals::TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)
    Internals::TCPStackHelper.any_instance.stubs(:start_main_loop).returns(nil)

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

  after do
    @s.shutdown
  end

  it 'invokes handlers on receipt of a message' do
    handler_invoked = false

    # Change the handler
    @s.add_handler(@auth_app_id, auth: true) { handler_invoked = true }
    
    avps = [AVP.create("Auth-Application-Id", @auth_app_id),
            AVP.create('Origin-Host', 'bob'),
            AVP.create("Destination-Host", "rkd2.local"),
            AVP.create("Destination-Realm", "my-realm")]

    msg = Message.new(command_code: 1000, hbh: 1, ete: 1,
                              app_id: @auth_app_id, avps: avps).to_wire

    @s.handle_message(msg, nil)

    handler_invoked.must_equal true
  end
end
