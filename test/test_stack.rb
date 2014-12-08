require 'minitest_helper'
require 'diameter/stack'
require 'mocha/mini_test'

describe 'Stack', 'A client DiameterStack' do

  before do
    # Mock out the interactions with the real world
    @s = Stack.new("testhost", "testrealm")
  end

  it 'moves into WAITING on initial connection' do
    socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')
    @s.peer_state('bob').must_equal :WAITING
  end

  it 'moves into UP when a successful CEA is received' do
    socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'bob')]
    cea = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: false, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire

    @s.handle_message(cea, socket_id)

    @s.peer_state('bob').must_equal :UP
  end

  it 'wait_for_state_change triggers when a successful CEA is received' do
    socket_id = 1004

    TCPStackHelper.any_instance.stubs(:setup_new_connection).returns(socket_id)
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)

    peer = @s.connect_to_peer('aaa://localhost', 'bob', 'bob-realm')

    avps = [AVP.create('Origin-Host', 'bob')]
    cea = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: false, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire

    state_has_changed_q = Queue.new

    Thread.new do
      peer.wait_for_state_change :UP
      state_has_changed_q.push 1
    end

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
end

describe 'Stack', 'A server DiameterStack' do

  before do
    # Mock out the interactions with the real world
    TCPStackHelper.any_instance.stubs(:send).with { |x, _c| x[0] == "\x01" }.returns(nil)
    TCPStackHelper.any_instance.stubs(:start_main_loop).returns(nil)

    @s = Stack.new("testhost", "testrealm")
    @s.start
  end

  it 'moves from CLOSED into UP when a CER is received' do
    @s.peer_state('bob').must_equal :CLOSED

    avps = [AVP.create('Origin-Host', 'bob')]
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
end
