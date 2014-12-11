require 'diameter/stack'
require 'diameter/avp'

class CxHandler

  def initialize(stack)
    @stack = stack
  end

  def answer_mar(mar)
    maa = mar.create_answer(2001, copying_avps: ["Session-Id", "Auth-Session-State", "Public-Identity", "User-Name"])
    maa.avps += [AVP.create("SIP-Number-Auth-Items", 1),
                 AVP.create("SIP-Auth-Data-Item",
                            [AVP.create("SIP-Authentication-Scheme", "SIP Digest")])]
    maa
  end

  def handle_request(req, cxn)
    ans = case req.command_code
          when 303
            answer_mar(req)
          else
            fail
          end
    @stack.send_answer(ans, cxn)
  end
end

server_stack = Stack.new("rkd2.local", "my-realm", port: 3869)
handler = CxHandler.new(server_stack)
server_stack.add_handler(16777216, auth: true, vendor: 10415) {|req, cxn| handler.handle_request(req, cxn) }
server_stack.listen_for_tcp
server_stack.start


client_stack = Stack.new("rkd.local", "my-realm")
client_stack.add_handler(16777216, auth: true, vendor: 10415) { nil }
client_stack.start
peer = client_stack.connect_to_peer("aaa://127.0.0.1:3869", "rkd2.local", "my-realm")

peer.wait_for_state_change :UP

puts 'peer is up'

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

mar = client_stack.new_request(303, app_id: 16777216, proxyable: false, retransmitted: false, error: false, avps: avps)

maa = client_stack.send_message(mar)
puts maa.value
