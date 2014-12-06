require 'diameter/stack'
require 'diameter/avp'

s = Stack.new
s.start
peer = s.connect_to_peer("aaa://54.154.3.120:3868", "hss.open-ims.test", "open-ims.test")

peer.wait_for_state_change :UP

puts 'up'

avps = [AVP.create("Vendor-Specific-Application-Id",
                   [AVP.create("Vendor-Id", 10415),
                    AVP.create("Auth-Application-Id", 16777216)]),
        AVP.create("Session-Id", "one"),
        AVP.create("Destination-Host", "hss.open-ims.test"),
        AVP.create("Destination-Realm", "open-ims.test"),
        AVP.create("Auth-Session-State", 0),
        AVP.create("User-Name", "alice@open-ims.test"),
        AVP.create("Public-Identity", "sip:alice@open-ims.test"),
        AVP.create("Server-Name", "sip:scscf@open-ims.test"),
        AVP.create("SIP-Number-Auth-Items", 1),
        AVP.create("SIP-Auth-Data-Item",
                   [AVP.create("SIP-Authentication-Scheme", "Unknown")]),
       ]

mar = s.new_request(303, app_id: 16777216, proxyable: false, retransmitted: false, error: false, avps: avps)

puts s.send_message(mar)
