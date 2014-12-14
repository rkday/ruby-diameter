require 'minitest_helper'
require 'diameter/stack'
require 'diameter/avp'

include Diameter

describe 'Stack interactions' do

  before do
    @server_stack = Stack.new("rkd2.local", "my-realm", port: 3869)
    @server_stack.add_handler(16777216, auth: true, vendor: 10415) do |req, cxn|
      avps = [AVP.create('User-Name', 'shibboleth')]
      @server_stack.send_answer(req.create_answer(2001, avps: avps), cxn)
    end
    @server_stack.listen_for_tcp
    @server_stack.start

    @client_stack = Stack.new("rkd.local", "my-realm")
    @client_stack.add_handler(16777216, auth: true, vendor: 10415) { nil }
    @client_stack.start
    @peer = @client_stack.connect_to_peer("aaa://127.0.0.1:3869", "rkd2.local", "my-realm")

    @peer.wait_for_state_change :UP
  end

  after do
    @server_stack.shutdown
    @client_stack.shutdown
  end
  
  it "can send a request from one stack and have the other stack's handler respond" do
    avps = [AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", 10415),
                        AVP.create("Auth-Application-Id", 16777216)]),
            AVP.create("Session-Id", "one"),
            AVP.create("Destination-Host", "rkd2.local"),
            AVP.create("Destination-Realm", "my-realm"),
            AVP.create("Auth-Session-State", 0),
            AVP.create("User-Name", "alice@open-ims.test"),
            AVP.create("Public-Identity", "sip:alice@open-ims.test"),
            AVP.create("Server-Name", "sip:scscf@open-ims.test"),
            AVP.create("SIP-Number-Auth-Items", 1),
            AVP.create("SIP-Auth-Data-Item",
                       [AVP.create("SIP-Authentication-Scheme", "Unknown")]),
           ]

    mar = Message.new(command_code: 303, app_id: 16777216, avps: avps)

    maa = @client_stack.send_request(mar)
    maa.value['User-Name'][0].octet_string.must_equal 'shibboleth'
  end

  it "can't send a request over a closed connection" do
    @server_stack.add_handler(16777216, auth: true, vendor: 10415) do |req, cxn|
      @server_stack.close(cxn)
    end

    avps = [AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", 10415),
                        AVP.create("Auth-Application-Id", 16777216)]),
            AVP.create("Session-Id", "one"),
            AVP.create("Destination-Host", "rkd2.local"),
            AVP.create("Destination-Realm", "my-realm"),
            AVP.create("Auth-Session-State", 0),
            AVP.create("User-Name", "alice@open-ims.test"),
            AVP.create("Public-Identity", "sip:alice@open-ims.test"),
            AVP.create("Server-Name", "sip:scscf@open-ims.test"),
            AVP.create("SIP-Number-Auth-Items", 1),
            AVP.create("SIP-Auth-Data-Item",
                       [AVP.create("SIP-Authentication-Scheme", "Unknown")]),
           ]

    mar = Message.new(command_code: 303, app_id: 16777216, avps: avps)

    maa = @client_stack.send_request(mar)
    sleep 0.1
    if RUBY_ENGINE != 'rbx'
      proc do maa = @client_stack.send_request(mar) end.must_raise IOError
    else
      proc do maa = @client_stack.send_request(mar) end.must_raise Errno::EBADF
    end
  end
end
