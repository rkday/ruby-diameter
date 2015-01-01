require 'uri'
require 'socket'
require 'diameter/peer'
require 'diameter/message'
require 'diameter/stack_transport_helpers'
require 'diameter/diameter_logger'
require 'concurrent'
require 'dnsruby'

module Diameter
  class Stack
    include Internals

    # @!group Setup methods

    # Stack constructor.
    #
    # @note The stack does not advertise any applications to peers by
    #  default - {#add_handler} must be called early on.
    #
    # @param host [String] The Diameter Identity of this stack (for
    #  the Origin-Host AVP).
    # @param realm [String] The Diameter realm of this stack (for
    #  the Origin-Realm AVP).
    # @option opts [Fixnum] timeout (60)
    #   The number of seconds to wait for an answer before notifying
    #   the caller of a timeout and forgetting about the request.
    def initialize(host, realm, opts={})
      @local_host = host
      @local_realm = realm

      @auth_apps = []
      @acct_apps = []

      @pending_ete = {}

      @tcp_helper = TCPStackHelper.new(self)
      @peer_table = {}
      @handlers = {}

      @answer_timeout = opts.fetch(:timeout, 60)

      @threadpool = Concurrent::ThreadPoolExecutor.new(
                                                       min_threads: 5,
                                                       max_threads: 5,
                                                       max_queue: 1,
                                                       overflow_policy: :caller_runs
                                                       )

      @res = Dnsruby::Resolver.new
      Diameter.logger.log(Logger::INFO, 'Stack initialized')
    end

    # Complete the stack initialization and begin reading from the TCP connections.
    def start
      @tcp_helper.start_main_loop
    end

    # Begins listening for inbound Diameter connections (making this a
    # Diameter server instead of just a client).
    #
    # @param port [Fixnum] The TCP port to listen on (default 3868)
    def listen_for_tcp(port=3868)
      @tcp_helper.setup_new_listen_connection("0.0.0.0", port)
    end

    # Adds a handler for a specific Diameter application.
    #
    # @note If you expect to only send requests for this application,
    #  not receive them, the block can be a no-op (e.g. `{ nil }`)
    #
    # @param app_id [Fixnum] The Diameter application ID.
    # @option opts [true, false] auth
    #   Whether we should advertise support for this application in
    #   the Auth-Application-ID AVP. Note that at least one of auth or
    #   acct must be specified.
    # @option opts [true, false] acct
    #   Whether we should advertise support for this application in
    #   the Acct-Application-ID AVP. Note that at least one of auth or
    #   acct must be specified.
    # @option opts [Fixnum] vendor
    #  If we should advertise support for this application in a
    #  Vendor-Specific-Application-Id AVP, this specifies the
    #  associated Vendor-Id.
    #
    # @yield [req, cxn] Passes a Diameter message (and its originating
    #  connection) for application-specific handling.
    # @yieldparam [Message] req The parsed Diameter message from the peer.
    # @yieldparam [Socket] cxn The TCP connection to the peer, to be
    #  passed to {Stack#send_answer}.
    def add_handler(app_id, opts={}, &blk)
      vendor = opts.fetch(:vendor, 0)
      auth = opts.fetch(:auth, false)
      acct = opts.fetch(:acct, false)

      raise ArgumentError.new("Must specify at least one of auth or acct") unless auth or acct
      
      @acct_apps << [app_id, vendor] if acct
      @auth_apps << [app_id, vendor] if auth
      
      @handlers[app_id] = blk
    end

    # @!endgroup

    # This shuts the stack down, closing all TCP connections and
    # terminating any background threads still waiting for an answer.
    def shutdown
      @tcp_helper.shutdown
      @pending_ete.each do |ete, q|
        Diameter.logger.debug("Shutting down queue #{q} as no answer has been received with EtE #{ete}")
        q.push :shutdown
      end
      @threadpool.kill
      @threadpool.wait_for_termination(5)
    end

    # Closes the given connection, blanking out any internal data
    # structures associated with it.
    #
    # Likely to be moved to the Peer object in a future release/
    #
    # @param connection [Socket] The connection to close.
    def close(connection)
      @tcp_helper.close(connection)
    end
    
    # @!group Peer connections and message sending

    def connect_to_realm(realm)
      possible_peers = []
      @res.query("_diameter._tcp.#{realm}", "SRV").each_answer do |a|
        possible_peers << {name: a.target.to_s, port: a.port, priority: a.priority, weight: a.weight}
      end

      # Prefer the lowest priority and the highest weight
      possible_peers.sort!{ |a, b| (a[:priority] <=> b[:priority]) || (b[:weight] <=> a[:weight])}
      Diameter.logger.debug("Sorted list of peers for realm #{realm} is #{possible_peers.inspect}")

      primary = possible_peers[0]

      url = "aaa://#{primary[:name]}:#{primary[:port]}"
      Diameter.logger.info("Primary peer for realm #{realm} is #{primary[:name]}, (#{url})")
      connect_to_peer(url, primary[:name], realm)
    end
    
    # Creates a Peer connection to a Diameter agent at the specific
    # network location indicated by peer_uri.
    #
    # @param peer_uri [URI] The aaa:// URI identifying the peer. Should
    #   contain a hostname/IP; may contain a port (default 3868).
    # @param peer_host [String] The DiameterIdentity of this peer, which
    #   will uniquely identify it in the peer table.
    # @param realm [String] The Diameter realm of this peer.
    def connect_to_peer(peer_uri, peer_host, realm)
      uri = URI(peer_uri)
      cxn = @tcp_helper.setup_new_connection(uri.host, uri.port)
      avps = [AVP.create('Origin-Host', @local_host),
              AVP.create('Origin-Realm', @local_realm),
              AVP.create('Host-IP-Address', IPAddr.new('127.0.0.1')),
              AVP.create('Vendor-Id', 100),
              AVP.create('Product-Name', 'ruby-diameter')
             ]
      avps += app_avps
      cer_bytes = Message.new(version: 1, command_code: 257, app_id: 0, request: true, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire
      @tcp_helper.send(cer_bytes, cxn)
      @peer_table[peer_host] = Peer.new(peer_host)
      @peer_table[peer_host].state = :WAITING
      @peer_table[peer_host].cxn = cxn
      @peer_table[peer_host]
      # Will move to :UP when the CEA is received
    end

    # Sends a Diameter request. This is routed to an appropriate peer
    # based on the Destination-Host AVP.
    #
    # This adds this stack's Origin-Host and Origin-Realm AVPs, if
    # those AVPs don't already exist.
    #
    # @param req [Message] The request to send.
    def send_request(req)
      fail "Must pass a request" unless req.request
      req.add_origin_host_and_realm(@local_host, @local_realm) 
      peer_name = req.avp_by_name('Destination-Host').octet_string
      state = peer_state(peer_name)
      if state == :UP
        peer = @peer_table[peer_name]
        @tcp_helper.send(req.to_wire, peer.cxn)
        q = Queue.new
        @pending_ete[req.ete] = q

        # Time this request out if no answer is received
        Concurrent::timer(@answer_timeout) do
          q = @pending_ete.delete(req.ete)
          if q
            q.push(:timeout)
          end
        end
            
        p = Concurrent::Promise.execute(executor: @threadpool) {
          Diameter.logger.debug("Waiting for answer to message with EtE #{req.ete}, queue #{q}")
          val = q.pop
          Diameter.logger.debug("Promise fulfilled for message with EtE #{req.ete}")
          val
        }
        return p
      else
        Diameter.logger.log(Logger::WARN, "Peer #{peer_name} is in state #{state} - cannot route")
      end
    end

    # Sends a Diameter answer. This is sent over the same connection
    # the request was received on (which needs to be passed into to
    # this method).
    #
    # This adds this stack's Origin-Host and Origin-Realm AVPs, if
    # those AVPs don't already exist.
    #
    # @param ans [Message] The Diameter answer
    # @param original_cxn [Socket] The connection which the request
    #   came in on. This will have been passed to the block registered
    #   with {Stack#add_handler}.
    def send_answer(ans, original_cxn)
      fail "Must pass an answer" unless ans.answer
      ans.add_origin_host_and_realm(@local_host, @local_realm) 
      @tcp_helper.send(ans.to_wire, original_cxn)
    end

    # Retrieves the current state of a peer, defaulting to :CLOSED if
    # the peer does not exist.
    #
    # @param id [String] The Diameter identity of the peer.
    # @return [Keyword] The state of the peer (:UP, :WAITING or :CLOSED).
    def peer_state(id)
      if !@peer_table.key? id
        :CLOSED
      else
        @peer_table[id].state
      end
    end

    # @!endgroup
    
    # @private
    # Handles a Diameter request straight from a network connection.
    # Intended to be called by TCPStackHelper after it retrieves a
    # message, not directly by users.
    def handle_message(msg_bytes, cxn)
      # Common processing - ensure that this message has come in on this
      # peer's expected connection, and update the last time we saw
      # activity on this peer
      msg = Message.from_bytes(msg_bytes)
      Diameter.logger.debug("Handling message #{msg}")
      peer = msg.avp_by_name('Origin-Host').octet_string
      if @peer_table[peer]
        @peer_table[peer].reset_timer
        unless @peer_table[peer].cxn == cxn
          Diameter.logger.log(Logger::WARN, "Ignoring message - claims to be from #{peer} but comes from #{cxn} not #{@peer_table[peer].cxn}")
        end
      end

      if msg.command_code == 257 && msg.answer
        handle_cea(msg)
      elsif msg.command_code == 257 && msg.request
        handle_cer(msg, cxn)
      elsif msg.command_code == 280 && msg.request
        handle_dwr(msg, cxn)
      elsif msg.command_code == 280 && msg.answer
        # No-op - we've already updated our timestamp
      elsif msg.answer
        handle_other_answer(msg, cxn)
      elsif @handlers.has_key? msg.app_id
        @handlers[msg.app_id].call(msg, cxn)
      else
        Diameter.logger.warn("Ignoring message from unrecognised application #{msg.app_id} (Command-Code #{msg.command_code})")
      end
    end

    private

    def app_avps
      avps = []
      
      @auth_apps.each do |app_id, vendor|
        avps << if vendor == 0
                  AVP.create("Auth-Application-Id", app_id)
                else
                  AVP.create("Vendor-Specific-Application-Id",
                             [AVP.create("Auth-Application-Id", app_id),
                              AVP.create("Vendor-Id", vendor)])
                end
      end

      @acct_apps.each do |app_id, vendor|
        avps << if vendor == 0
                  AVP.create("Acct-Application-Id", app_id)
                else
                  AVP.create("Vendor-Specific-Application-Id",
                             [AVP.create("Acct-Application-Id", app_id),
                              AVP.create("Vendor-Id", vendor)])
                end
      end
      
      avps
    end

    def shared_apps(capabilities_msg)
      peer_apps = []

      app_avps = ["Auth-Application-Id", "Acct-Application-Id"]

      app_avps.each do |name|
        peer_apps += capabilities_msg.all_avps_by_name(name).collect(&:uint32)

        capabilities_msg.all_avps_by_name("Vendor-Specific-Application-Id").each do |avp|
          if avp.inner_avp(name)
            peer_apps << avp.inner_avp(name).uint32
          end
        end
      end

      Diameter.logger.debug("Received app IDs #{peer_apps} from peer, have apps #{@handlers.keys}")
      
      @handlers.keys.to_set & peer_apps.to_set
    end    
    
    def handle_cer(cer, cxn)
      if shared_apps(cer).empty?
        rc = 5010
      else
        rc = 2001
      end
      
      cea = cer.create_answer(rc, avps:
                              [AVP.create('Origin-Host', @local_host),
                               AVP.create('Origin-Realm', @local_realm)] + app_avps)

      @tcp_helper.send(cea.to_wire, cxn)

      if rc == 2001
        peer = cer.avp_by_name('Origin-Host').octet_string
        Diameter.logger.debug("Creating peer table entry for peer #{peer}")
        @peer_table[peer] = Peer.new(peer)
        @peer_table[peer].state = :UP
        @peer_table[peer].reset_timer
        @peer_table[peer].cxn = cxn
      else
        @tcp_helper.close(cxn)
      end
    end

    def handle_cea(cea)
      peer = cea.avp_by_name('Origin-Host').octet_string
      if @peer_table.has_key? peer
        @peer_table[peer].state = :UP
        @peer_table[peer].reset_timer
      else
        Diameter.logger.warn("Ignoring CEA from unknown peer #{peer}")
        Diameter.logger.debug("Known peers are #{@peer_table.keys}")
      end
    end

    def handle_dpr
    end

    def handle_dpa
    end

    def handle_dwr(dwr, cxn)
      dwa = dwr.create_answer(2001, avps:
                              [AVP.create('Origin-Host', @local_host),
                               AVP.create('Origin-Realm', @local_realm)])

      @tcp_helper.send(dwa.to_wire, cxn)
      # send DWA
    end

    def handle_dwa
    end

    def handle_other_request
    end

    def handle_other_answer(msg, _cxn)
      Diameter.logger.debug("Handling answer with End-to-End identifier #{msg.ete}")
      q = @pending_ete[msg.ete]
      q.push msg
      Diameter.logger.debug("Passed answer to fulfil sender's Promise object'")
      @pending_ete.delete msg.ete
    end
  end
end
