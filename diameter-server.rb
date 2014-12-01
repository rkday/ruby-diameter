require_relative 'lib/diameter/avp.rb'
require_relative 'lib/diameter/message.rb'

require 'socket'

server = TCPServer.new 3868
client = server.accept

cer_header = client.recv(20)
cer = DiameterMessage.from_header(cer_header)
avps = client.recv(cer.length-20)
cer.parse_avps(avps)

puts cer
puts cer.getAVP("Origin-Host").getOctetString
cea = cer.response

cea.avps = [AVP.create("Result-Code", 2001),
            AVP.create("Origin-Host", "host.example.com"),
            AVP.create("Origin-Realm", "example.com"),
            AVP.create("Vendor-Id", 10415),
            AVP.create("Vendor-Specific-Application-Id",
                       [AVP.create("Vendor-Id", 10415),
                        AVP.create("Auth-Application-Id", 16777216)])
           ]

client.sendmsg(cea.to_wire)

mar_header = client.recv(20)
if mar_header.length == 0
  puts "No MAR sent"
else
  mar = DiameterMessage.from_header(mar_header)
  avps = client.recv(mar.length-20)
  mar.parse_avps(avps)

  puts mar
  puts mar.getAVP("Origin-Host")
  maa = mar.response

  maa.avps = [AVP.create("Result-Code", 2001),
              AVP.create("Origin-Host", "host.example.com"),
              AVP.create("Origin-Realm", "example.com"),
              AVP.create("Vendor-Id", 10415)]

  client.sendmsg(maa.to_wire)
end
