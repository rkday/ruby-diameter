require 'uri'
require 'socket'
require 'diameter/message'
require 'diameter/stack_transport_helpers'
require 'diameter/diameter_logger'
require 'concurrent'

# A Diameter peer entry in the peer table.
#
# @!attribute [rw] identity
#   [String] The DiameterIdentity of this peer
# @!attribute [rw] realm
#   [String] The Diameter realm of this peer
# @!attribute [rw] static
#   [true, false] Whether this peer was dynamically discovered (and so
#   might expire) or statically configured.
# @!attribute [rw] expiry_time
#   [Time] For a dynamically discovered peer, the time when it stops
#   being valid and dynamic discovery must happen again.
# @!attribute [rw] last_message_seen
#   [Time] The last time traffic was received from this peer. Used for
#   determining when to send watchdog messages, or for triggering failover.
# @!attribute [rw] cxn
#   [Socket] The underlying network connection to this peer.
# @!attribute [rw] state
#   [Keyword] The current state of this peer - :UP, :WATING or :CLOSED.

class Peer
  attr_accessor :identity, :static, :cxn, :realm, :expiry_time, :last_message_seen
  attr_reader :state

  def initialize(identity)
    @identity = identity
    @state = :CLOSED
    @state_change_q = Queue.new
  end

  # Blocks until the state of this peer changes to the desired value.
  #
  # @param state [Keyword] The state to change to.
  def wait_for_state_change(state)
    cur_state = @state
    while (cur_state != state)
      cur_state = @state_change_q.pop
    end
  end

  # @todo Add further checking, making sure that the transition to
  # new_state is valid according to the RFC 6733 state machine. Maybe
  # use the micromachine gem?
  def state=(new_state)
    Diameter.logger.log(Logger::DEBUG, "State of peer #{identity} changed from #{@state} to #{new_state}")
    @state = new_state
    @state_change_q.push new_state
  end

  # Resets the last message seen time. Should be called when a message
  # is received from this peer.
  def reset_timer
    self.last_message_seen = Time.now
  end
end

class Stack
  def initialize(host, realm, opts={})
    @local_host = host
    @local_realm = realm
    @local_port = opts[:port] || 3868

    @auth_apps = []
    @acct_apps = []

    @pending_ete = []

    @ete = 1
    @hbh = 1

    @tcp_helper = TCPStackHelper.new(self)
    @peer_table = {}
    @handlers = {}
    Diameter.logger.log(Logger::INFO, 'Stack initialized')
  end

  def new_request(code, options = {})
    DiameterMessage.new({ version: 1, command_code: code, hbh: next_hbh, ete: next_ete, request: true }.merge(options))
  end

  # @return [Fixnum] An End-to-End identifier number that has never
  # been issued before by this stack.
  def next_ete
    @ete += 1
  end

  # @return [Fixnum] A Hop-by-Hop identifier number that has never
  # been issued before by this stack.
  def next_hbh
    @hbh += 1
  end

  def start
    @tcp_helper.start_main_loop
  end

  def listen_for_tcp
    @tcp_helper.setup_new_listen_connection("0.0.0.0", @local_port)
  end

  # Creates a Peer connection to a Diameter agent at the specific
  # network location indicated by peer_uri.
  #
  # @param peer_uri [URI] The aaa:// URI identifying the peer. Should
  #   contain a hostname/IP; may contain a port (default 3868) and a
  #   transport param indicating TCP or SCTP (default TCP).
  # @param peer_host [String] The DiameterIdentity of this peer, which
  #   will uniquely identify it in the peer table.
  # @param realm [String] The Diameter realm of this peer.
  def connect_to_peer(peer_uri, peer_host, _realm)
    uri = URI(peer_uri)
    cxn = @tcp_helper.setup_new_connection(uri.host, uri.port)
    avps = [AVP.create('Origin-Host', @local_host),
            AVP.create('Origin-Realm', @local_realm),
            AVP.create('Host-IP-Address', IPAddr.new('127.0.0.1')),
            AVP.create('Vendor-Id', 100),
            AVP.create('Product-Name', 'ruby-diameter')
           ]
    avps += app_avps
    cer_bytes = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: true, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire
    @tcp_helper.send(cer_bytes, cxn)
    @peer_table[peer_host] = Peer.new(peer_host)
    @peer_table[peer_host].state = :WAITING
    @peer_table[peer_host].cxn = cxn
    @peer_table[peer_host]
    # Will move to :UP when the CEA is received
  end

  def disconnect_from_peer(_peer_host)
  end

  def timer_loop
  end

  def peer_state(id)
    if !@peer_table.key? id
      :CLOSED
    else
      @peer_table[id].state
    end
  end

  def shutdown_cleanly
  end

  def send_message(req)
    req.avps += [AVP.create('Origin-Host', @local_host),
                 AVP.create('Origin-Realm', @local_realm)]
    fail "Must pass a request" unless req.request
    q = Queue.new
    @pending_ete[req.ete] = q
    peer_name = req.avp_by_name('Destination-Host').octet_string
    state = peer_state(peer_name)
    if state == :UP
      peer = @peer_table[peer_name]
      @tcp_helper.send(req.to_wire, peer.cxn)
      p = Concurrent::Promise.execute {
        Diameter.logger.debug("Waiting for answer to message with EtE #{req.ete}")
        val = q.pop
        Diameter.logger.debug("Promise fulfilled for message with EtE #{req.ete}")
        val
      }
      return p
    else
      Diameter.logger.log(Logger::WARN, "Peer #{peer_name} is in state #{state} - cannot route")
    end
  end

  def send_answer(ans, original_cxn)
    ans.avps += [AVP.create('Origin-Host', @local_host),
                 AVP.create('Origin-Realm', @local_realm)]
    @tcp_helper.send(ans.to_wire, original_cxn)
  end
  
  def answer_for(req, response_code)
    req.create_answer(response_code)
  end

  def add_handler(app_id, opts={}, &blk)
    vendor = opts.fetch(:vendor, 0)
    auth = opts.fetch(:auth, false)
    acct = opts.fetch(:acct, false)

    raise ArgumentError.new("Must specify at least one of auth or acct") unless auth or acct
    
    @acct_apps << [app_id, vendor] if acct
    @auth_apps << [app_id, vendor] if auth
    
    @handlers[app_id] = blk
  end

  def handle_message(msg_bytes, cxn)
    # Common processing - ensure that this message has come in on this
    # peer's expected connection, and update the last time we saw
    # activity on this peer
    msg = DiameterMessage.from_bytes(msg_bytes)
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
      fail "Received unknown message of type #{msg.command_code}"
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
    peer_apps = capabilities_msg.all_avps_by_name("Auth-Application-Id").collect(&:uint32)
    peer_apps += capabilities_msg.all_avps_by_name("Acct-Application-Id").collect(&:uint32)

    capabilities_msg.all_avps_by_name("Vendor-Specific-Application-Id").each do |avp|
      if avp.inner_avp("Auth-Application-Id")
        peer_apps << avp.inner_avp("Auth-Application-Id").uint32
      end

      if avp.inner_avp("Acct-Application-Id")
        peer_apps << avp.inner_avp("Acct-Application-Id").uint32
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
    
    cea = answer_for(cer, rc)
    cea.avps = [AVP.create('Origin-Host', @local_host),
                AVP.create('Origin-Realm', @local_realm)] + app_avps

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
    # puts peer
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
    dwa = answer_for(dwr, 2001)
    dwa.avps = [AVP.create('Origin-Host', @local_host),
                AVP.create('Origin-Realm', @local_realm)]

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
