This repository contains a simple Diameter parser and stack in Ruby.

## Getting started

`functional_test/basic_stacks.rb` contains some code which can:

* Set a handler for a particular Diameter application
* Read Diameter messages off a TCP connection
* Parse them and read individual AVPs
* Create a response to Diameter messages
* Add AVPs (including string, integer and grouped AVPs)
* Send the response over the TCP connection

## Current state

The message parsing and sending code has been verified (using Wireshark to check that the parsed values are correct and that the sent message is valid).

The Diameter stack works for basic use - it can create/accept peer connections, do the CER/CEA exchange, and allows you to register handlers for Diameter applications.

Only a small handful of AVPs are implemented - more can be added just by editing the AVAILABLE_AVPS dictionary in  `constants.rb`, or at runtime by calling `AVP.define`.

## TODOs

### Infrastructure
* Set up handwritten documentation (readthedocs.org?)

### Completeness
* Implement more AVPs (at least all the RFC 3877 and all the 3GPP ones)
* Implement the remaining Derived AVP Data Formats (Time, UTF8String, DiameterURI, DiameterIdentity)
* continue to improve the YARD API documentation

### Stack
* Allow disconnecting from peers
* SCTP support
* Send watchdog requests on a timer and track unresponsive peers
* Handle failover/failback
* Handle more complex routing (e.g. based on realms or via a designated proxy)
* Provide proxy/redirect/relay function
* Flesh out the state machine, including e.g. disconnection support
* Dynamic peer discovery

### APIs
* Test the APIs in a variety of use-cases (e.g. server and client, test tools, maybe a real app?)

### Style
* Ensure conformance to https://github.com/bbatsov/ruby-style-guide

### Tests
* Set up an infrastructure for reading and parsing .pcap or PDML files, so parsed messages can be manually checked against Wireshark

### Portability
* Ruby 1.8? I'm not sure there will be demand.
* JRuby - either resolve issues with stack_transport_helpers or write a JRuby-specific version calling Java classes
