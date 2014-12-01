This repository contains a simple Diameter parser/message creation library in Ruby. In the future, it will also contain a Diameter stack in Ruby.

## Getting started

`diameter-server.rb` is some example code which can:

* Read Diameter messages off a TCP connection
* Parse them and read individual AVPs
* Create a response to Diameter messages
* Add AVPs (including string, integer and grouped AVPs)
* Send the response over the TCP connection

## Current state

The message parsing and sending code has been verified (using Wireshark to check that the parsed values are correct and that the sent message is valid).

There are no UTs, although they should be easy to add.

There's no full stack - you'll need to handle CERs and CEAs manually. For short scripted tests there should be no need to handle watchdog or disconnect requests.

Only a small handful of AVPs are implemented - more can be added just by editing the dictionary in the AVPNames class in `avp.rb`.
