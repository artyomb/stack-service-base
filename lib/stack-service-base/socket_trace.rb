module StackServiceBase
  module SocketTrace
    def bind(local_sockaddr)
      addr = Addrinfo.new(local_sockaddr)
      LOGGER.info "Socket Bind: http://#{arrd.ip_address}:#{addr.ip_port}"
      super
    end
    def setsockopt(level, optname, optval)
      LOGGER.info "Socket setsockopt: #{level}, #{optname}, #{optval}"
      super
    end
  end

  Socket.prepend SocketTrace
end