require 'uri'
require 'socket'
require 'diameter/message'
require 'diameter/stack_transport_helpers'

class Peer
  attr_accessor :identity, :static, :cxn, :realm, :expiry_time, :last_message_seen
  attr_reader :state

  def initialize
    @state_change_q = Queue.new
  end
  
  def wait_for_state_change(state)
    cur_state = @state
    while (cur_state != state)
      cur_state = @state_change_q.pop
    end
  end
  
  def state=(new_state)
    @state = new_state
    @state_change_q.push new_state
  end
  
  def reset_timer
    self.last_message_seen = Time.now
  end
  
end

class Stack
  def initialize
    @local_host = "rkd"
    @local_realm = "rkd-realm"
    @local_port = nil

    @auth_apps = [16777216]
    @acct_apps = []
    @vendor_auth_apps = []
    @vendor_acct_apps = []

    @pending_ete = []

    @ete = 1
    @hbh = 1
    
    @tcp_helper = TCPStackHelper.new(self)
    @peer_table = {}
  end

  def new_request(code, options={})
    DiameterMessage.new({version: 1, command_code: code, hbh: next_hbh, ete: next_ete, request: true}.merge(options))
  end
  
  def next_ete
    @ete += 1
  end

  def next_hbh
    @hbh += 1
  end

  def start
    @tcp_helper.start_main_loop
  end    
  
  def connect_to_peer(peer_uri, peer_host, realm)
    uri = URI(peer_uri)
    cxn = @tcp_helper.setup_new_connection(uri.host, uri.port)
    avps = [AVP.create("Origin-Host", @local_host),
            AVP.create("Origin-Realm", @local_realm),
            AVP.create("Host-IP-Address", IPAddr.new("127.0.0.1")),
            AVP.create("Vendor-Id", 100),
            AVP.create("Product-Name", "ruby-diameter"),
           ]
    avps += @auth_apps.collect { | code| AVP.create("Auth-Application-Id", code)}
    cer_bytes = DiameterMessage.new(version: 1, command_code: 257, app_id: 0, hbh: 1, ete: 1, request: true, proxyable: false, retransmitted: false, error: false, avps: avps).to_wire
    @tcp_helper.send(cer_bytes, cxn)
    @peer_table[peer_host] = Peer.new
    @peer_table[peer_host].state = :WAITING
    @peer_table[peer_host].cxn = cxn
    @peer_table[peer_host]
    # Will move to :UP when the CEA is received
  end

  def disconnect_from_peer(peer_host)
  end

  def timer_loop

  end
  
  def peer_state(id)
    if not @peer_table.has_key? id
      :CLOSED
    else
      @peer_table[id].state
    end
  end
  
  def shutdown_cleanly
  end

  def add_handler_for_app
  end

  def send_message(req, timeout=5)
    if req.request
      req.avps += [AVP.create("Origin-Host", @local_host),
                   AVP.create("Origin-Realm", @local_realm)]
      q = Queue.new
      @pending_ete[req.ete] = q
      peer_name = req.avp_by_name("Destination-Host").octet_string
      peer = @peer_table[peer_name]
      if peer.state == :UP
        puts "Sending over wire"
        @tcp_helper.send(req.to_wire, peer.cxn)
      end

      q.pop
    end
  end

  def answer_for(req)
    req.create_answer(@local_host)
  end

  def handle_message(msg_bytes, cxn)

    # Common processing - ensure that this message has come in on this
    # peer's expected connection, and update the last time we saw
    # activity on this peer
    msg = DiameterMessage.from_bytes(msg_bytes)
    peer = msg.avp_by_name("Origin-Host").octet_string
    if @peer_table[peer]
      @peer_table[peer].reset_timer
      fail "Connection hijacking" unless @peer_table[peer].cxn == cxn
    end
    
    if msg.command_code == 257 and msg.answer
      handle_cea(msg)
    elsif msg.command_code == 257 and msg.request
      handle_cer(msg, cxn)
    elsif msg.command_code == 280 and msg.request      
      handle_dwr(msg, cxn)
    elsif msg.command_code == 280 and msg.answer
      # No-op - we've already updated our timestamp
    elsif msg.answer
      handle_other_answer(msg, cxn)
    else
      fail "Received unknown message of type #{msg.command_code}"
    end
  end

  private
  
  def handle_cer(cer, cxn)
    peer = cer.avp_by_name("Origin-Host").octet_string
    cea = answer_for(cer)
    @tcp_helper.send(cea.to_wire, cxn)
    @peer_table[peer] = Peer.new
    @peer_table[peer].state = :UP
    @peer_table[peer].reset_timer
    @peer_table[peer].cxn = cxn
    # send cea
  end

  def handle_cea(cea)
    peer = cea.avp_by_name("Origin-Host").octet_string
    puts peer
    @peer_table[peer].state = :UP
    @peer_table[peer].reset_timer
    puts cea
  end

  def handle_dpr
  end

  def handle_dpa
  end

  def handle_dwr(dwr, cxn)
    dwa = answer_for(dwr)
    dwa.avps = [AVP.create("Origin-Host", "rkd"),
                AVP.create("Origin-Realm", "rkd-realm"),
                AVP.create("Result-Code", 2001)]

    @tcp_helper.send(dwa.to_wire, cxn)
    # send DWA
  end

  def handle_dwa
  end

  def handle_other_request
  end
  
  def handle_other_answer(msg, cxn)
    q = @pending_ete[msg.ete]
    q.push msg
    @pending_ete.delete msg.ete
  end
end
