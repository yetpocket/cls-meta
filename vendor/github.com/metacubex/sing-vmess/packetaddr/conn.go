package packetaddr

import (
	"net"

	"github.com/sagernet/sing/common"
	"github.com/sagernet/sing/common/buf"
	"github.com/sagernet/sing/common/bufio"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

var _ N.PacketReadWaitCreator = (*PacketConn)(nil)

type PacketConn struct {
	N.NetPacketConn
	bindAddr M.Socksaddr
}

func NewConn(conn net.PacketConn, bindAddr M.Socksaddr) *PacketConn {
	return &PacketConn{
		bufio.NewPacketConn(conn),
		bindAddr,
	}
}

func NewBindConn(conn net.Conn) *PacketConn {
	return &PacketConn{
		bufio.NewUnbindPacketConn(conn),
		M.Socksaddr{},
	}
}

func (c *PacketConn) RemoteAddr() net.Addr {
	return c.bindAddr
}

func (c *PacketConn) Read(b []byte) (n int, err error) {
	n, _, err = c.ReadFrom(b)
	return
}

func (c *PacketConn) Write(b []byte) (n int, err error) {
	return c.WriteTo(b, c.RemoteAddr())
}

func (c *PacketConn) ReadFrom(p []byte) (n int, addr net.Addr, err error) {
	buffer := buf.With(p)
	var destination M.Socksaddr
	destination, err = c.ReadPacket(buffer)
	if err != nil {
		return
	}
	n = copy(p, buffer.Bytes())
	if destination.IsFqdn() {
		addr = destination
	} else {
		addr = destination.UDPAddr()
	}
	return
}

func (c *PacketConn) WriteTo(p []byte, addr net.Addr) (n int, err error) {
	destination := M.SocksaddrFromNet(addr)
	buffer := buf.NewSize(AddressSerializer.AddrPortLen(destination) + len(p))
	defer buffer.Release()
	err = AddressSerializer.WriteAddrPort(buffer, destination)
	if err != nil {
		return
	}
	common.Must1(buffer.Write(p))
	return c.NetPacketConn.WriteTo(buffer.Bytes(), c.bindAddr.UDPAddr())
}

func (c *PacketConn) ReadPacket(buffer *buf.Buffer) (destination M.Socksaddr, err error) {
	_, err = c.NetPacketConn.ReadPacket(buffer)
	if err != nil {
		return
	}
	destination, err = AddressSerializer.ReadAddrPort(buffer)
	if err != nil {
		return
	}
	return destination.Unwrap(), nil
}

func (c *PacketConn) WritePacket(buffer *buf.Buffer, destination M.Socksaddr) error {
	if destination.IsFqdn() {
		return E.Extend(ErrFqdnUnsupported, destination.Fqdn)
	}
	header := buf.With(buffer.ExtendHeader(AddressSerializer.AddrPortLen(destination)))
	err := AddressSerializer.WriteAddrPort(header, destination)
	if err != nil {
		return err
	}
	return c.NetPacketConn.WritePacket(buffer, c.bindAddr)
}

func (c *PacketConn) FrontHeadroom() int {
	return M.MaxIPSocksaddrLength
}

func (c *PacketConn) Upstream() any {
	return c.NetPacketConn
}

func (c *PacketConn) CreateReadWaiter() (N.PacketReadWaiter, bool) {
	prw, isReadWaiter := bufio.CreatePacketReadWaiter(c.NetPacketConn)
	if isReadWaiter {
		return &readWaiterPacketConn{
			readWaiter: prw,
			bindAddr:   c.bindAddr,
		}, true
	}
	return nil, false
}

var _ N.PacketReadWaiter = (*readWaiterPacketConn)(nil)

type readWaiterPacketConn struct {
	readWaiter N.PacketReadWaiter
	bindAddr   M.Socksaddr
	buffer     *buf.Buffer
}

func (c *readWaiterPacketConn) InitializeReadWaiter(newBuffer func() *buf.Buffer) {
	if newBuffer != nil {
		newBuffer = func() *buf.Buffer {
			c.buffer = newBuffer()
			return c.buffer
		}
	}
	c.readWaiter.InitializeReadWaiter(newBuffer)
}

func (c *readWaiterPacketConn) WaitReadPacket() (destination M.Socksaddr, err error) {
	_, err = c.readWaiter.WaitReadPacket()
	if err != nil {
		c.buffer = nil
		return
	}
	destination, err = AddressSerializer.ReadAddrPort(c.buffer)
	if err != nil {
		c.buffer.Release()
	}
	c.buffer = nil
	return
}

func (c *readWaiterPacketConn) Upstream() any {
	return c.readWaiter
}
