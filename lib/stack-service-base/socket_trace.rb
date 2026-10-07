module StackServiceBase
  module SocketTrace
    def bind(local_sockaddr)
      addr = local_sockaddr.is_a?(Addrinfo) ? local_sockaddr : Addrinfo.new(local_sockaddr)
      # LOGGER.debug "Socket Bind: http://#{addr.ip_address}:#{addr.ip_port}"
      super
    end
    def setsockopt(level, optname, optval)
      # LOGGER.debug "Socket setsockopt: #{level}, #{optname}, #{optval}"
      super
    end
  end

  Socket.prepend SocketTrace
end
