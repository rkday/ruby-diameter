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

There's no full stack - you'll need to handle CERs and CEAs manually. For short scripted tests there should be no need to handle watchdog or disconnect requests.

Only a small handful of AVPs are implemented - more can be added just by editing the dictionary in the AVPNames class in `avp.rb`.

## TODOs

### Infrastructure
* Package as a gem
* Set up appropriate YARD API documentation
* Set up handwritten documentation

### Completeness
* Implement more AVPs
* Make it possible to add AVPs without code edits (loading CSV files?)
* Implement the remaining Derived AVP Data Formats (Time, UTF8String, DiameterURI, DiameterIdentity)

### Stack
* Add a stack that can:
  * handle TCP/SCTP connections to peers behind the scenes
  * handle CER/CEA, DWR/DWA and DPR/DPA messages automatically
  * handle failover/failback

### APIs
* Test the APIs in a variety of use-cases (e.g. server and client, test tools, maybe a real app?)

### Style
* Ensure conformance to https://github.com/bbatsov/ruby-style-guide

### Tests
* Have more testcases
* Set up an infrastructure for reading and parsing .pcap files, so parsed messages can be manually checked against Wireshark
