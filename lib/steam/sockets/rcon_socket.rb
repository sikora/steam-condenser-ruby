# This code is free software; you can redistribute it and/or modify it under
# the terms of the new BSD License.
#
# Copyright (c) 2008-2013, Sebastian Staudt

require 'ipaddr'
require 'socket'
require 'timeout'

require 'errors/rcon_ban_error'
require 'errors/rcon_no_auth_error'
require 'errors/timeout_error'
require 'steam/packets/rcon/rcon_packet'
require 'steam/packets/rcon/rcon_packet_factory'
require 'steam/sockets/steam_socket'

# This class represents a socket used for RCON communication with game servers
# based on the Source engine (e.g. Team Fortress 2, Counter-Strike: Source)
#
# The Source engine uses a stateful TCP connection for RCON communication and
# uses an additional socket of this type to handle RCON requests.
#
# @author Sebastian Staudt
class RCONSocket

  include SteamSocket

  # Creates a new TCP socket to communicate with the server on the given IP
  # address and port
  #
  # @param [String, IPAddr] ip Either the IP address or the DNS name of the
  #        server
  # @param [Fixnum] port The port the server is listening on
  def initialize(ip, port)
    ip = IPSocket.getaddress(ip) unless ip.is_a? IPAddr

    @ip     = ip
    @port   = port
  end

  # Closes the underlying TCP socket if it exists
  #
  # SteamSocket#close
  def close
    super unless @socket.nil?
  end

  # Connects a new TCP socket to the server
  #
  # @raise [SteamCondenser::TimeoutError] if the connection could not be
  #        established
  def connect
    begin
      timeout(@@timeout / 1000.0) { @socket = TCPSocket.new @ip, @port }
    rescue Timeout::Error
      raise SteamCondenser::TimeoutError
    end
  end

  # Sends the given RCON packet to the server
  #
  # @param [RCONPacket] data_packet The RCON packet to send to the server
  # @see #connect
  def send(data_packet)
    connect if @socket.nil? || @socket.closed?

    super
  end

  # Reads a packet from the socket
  #
  # The Source RCON protocol allows packets of an arbitrary sice transmitted
  # using multiple TCP packets. The data is received in chunks and concatenated
  # into a single response packet.
  #
  # @raise [RCONBanError] if the IP of the local machine has been banned on the
  #        game server
  # @raise [RCONNoAuthException] if an authenticated connection has been
  #        dropped by the server
  # @return [RCONPacket] The packet replied from the server
  def reply
    begin
      if receive_packet(4) == 0
        @socket.close
        raise RCONNoAuthError
      end
    rescue Errno::ECONNRESET
      raise RCONBanError
    end

    remaining_bytes = @buffer.long

    packet_data = ''
    begin
      received_bytes = receive_packet remaining_bytes
      remaining_bytes -= received_bytes
      packet_data << @buffer.get
    end while remaining_bytes > 0

    packet = RCONPacketFactory.packet_from_data(packet_data)

    puts "Received packet of type \"#{packet.class}\"." if $DEBUG

    packet
  end

end
