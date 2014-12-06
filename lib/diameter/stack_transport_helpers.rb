require 'uri'
require 'socket'
require 'diameter/message'
require 'diameter/avp'

class StackHelper
  def initialize(stack)
    @all_connections = []
    @data = {}
    @stack = stack
    @loop_thread = nil
  end
  
  def start_main_loop
    @loop_thread =
      Thread.new do
      loop do
        main_loop
      end
    end
  end

  def wakeup
    @loop_thread.raise
  end
  
  def main_loop
    #puts "main loop running"

    begin
      rs, _ws, es = IO.select(@all_connections, [], @all_connections)
    rescue RuntimeError
      return
    end
    
    #puts "select returned: #{rs}, #{es}"

    if es
      for e in es
        puts "Got error: #{e}"
      end
    end

    if rs
      for r in rs
        #puts r

        existing_data = @data[r]
        if existing_data.length < 4
          msg, src = r.recvfrom_nonblock(4-existing_data.length)
          if msg == ""
            # Connection closed
            r.close
            @all_connections.delete r
            @data.delete r
          else
            existing_data += msg
          end
        end

        expected_len = -1
        if existing_data.length >= 4
          #puts existing_data[0..4].inspect
          expected_len = DiameterMessage.length_from_header(existing_data[0..4])
          #puts expected_len
          msg, src = r.recvfrom_nonblock(expected_len-existing_data.length)
          existing_data += msg
          #puts existing_data.inspect
          if msg == ""
            # Connection closed
            r.close
            @all_connections.delete r
            @data.delete r
          end
        end

        if existing_data.length == expected_len
          @stack.handle_message(existing_data, r)
          @data[r] = ""
        else
          @data[r] = existing_data
        end
      end
    end
  end

  def send(bytes, connection)
    connection.sendmsg(bytes)
  end
end

class TCPStackHelper < StackHelper
  def setup_new_connection(host, port)
    sd = Socket.new( Socket::AF_INET, Socket::SOCK_STREAM, 0 )
    sd.connect(Socket.pack_sockaddr_in(port, host))
    @all_connections.push sd
    @data[sd] = ""
    self.wakeup
    sd
  end

  def setup_new_listen_connection(host, port)
  end

  def accept_loop
    rs, _ws, es = IO.select(@listen_connections, [], @listen_connections)
    for e in es
      #puts e
    end

    for r in rs
      @all_connections.push r.accept_nonblock
    end
  end
end

class SCTPStackHelper
  def setup_new_connection(host, port)
    sd = Socket.new( Socket::AF_INET, Socket::SOCK_STREAM, 0 )
    sd.connect(Socket.pack_sockaddr_in(8090, "1.3.5.7"))    
  end

  def setup_new_listen_connection(host, port)
    
  end

  def send(bytes, connection)

  end
end
