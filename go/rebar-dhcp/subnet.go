// Example of minimal DHCP server:

package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"log"
	"net"
	"text/template"
	"time"

	rebar "github.com/digitalrebar/digitalrebar/go/rebar-api/api"
	"github.com/digitalrebar/digitalrebar/go/rebar-dhcp/dhcp"
	"github.com/willf/bitset"
)

// Option id number from DHCP RFC 2132 and 2131
// Value is a string version of the value
type Option struct {
	Code  dhcp.OptionCode `json:"id"`
	Value string          `json:"value"`
}

func (o *Option) RenderToDHCP(srcOpts map[int]string) (code dhcp.OptionCode, val []byte, err error) {
	code = dhcp.OptionCode(o.Code)
	tmpl, err := template.New("dhcp_option").Parse(o.Value)
	if err != nil {
		return code, nil, err
	}
	buf := &bytes.Buffer{}
	if err := tmpl.Execute(buf, srcOpts); err != nil {
		return code, nil, err
	}
	val, err = convertOptionValueToByte(code, buf.String())
	return code, val, err
}

type Lease struct {
	Ip         net.IP    `json:"ip"`
	Mac        string    `json:"mac"`
	Valid      bool      `json:"valid"`
	ExpireTime time.Time `json:"expire_time"`
	State      string
}

func (l *Lease) Phantom() bool {
	addr, _ := net.ParseMAC(l.Mac)
	return addr[0] == 00 && addr[1] == 0x53
}

type Binding struct {
	Ip         net.IP    `json:"ip"`
	Mac        string    `json:"mac"`
	Options    []*Option `json:"options,omitempty"`
	NextServer *string   `json:"next_server,omitempty"`
}

type Subnet struct {
	Name              string
	Subnet            *MyIPNet
	NextServer        *net.IP `json:",omitempty"`
	ActiveStart       net.IP
	ActiveEnd         net.IP
	ActiveLeaseTime   time.Duration
	ReservedLeaseTime time.Duration
	OnlyBoundLeases   bool
	Leases            map[string]*Lease
	Bindings          map[string]*Binding
	Options           []*Option // Options to send to DHCP Clients
	TenantId          int
}

func NewSubnet() *Subnet {
	return &Subnet{
		Leases:   make(map[string]*Lease),
		Bindings: make(map[string]*Binding),
		Options:  make([]*Option, 0),
	}
}

type apiSubnet struct {
	Name              string     `json:"name"`
	Subnet            string     `json:"subnet"`
	NextServer        *string    `json:"next_server,omitempty"`
	ActiveStart       string     `json:"active_start"`
	ActiveEnd         string     `json:"active_end"`
	ActiveLeaseTime   int        `json:"active_lease_time"`
	ReservedLeaseTime int        `json:"reserved_lease_time"`
	OnlyBoundLeases   bool       `json:"only_bound_leases"`
	Leases            []*Lease   `json:"leases,omitempty"`
	Bindings          []*Binding `json:"bindings,omitempty"`
	Options           []*Option  `json:"options,omitempty"`
	TenantId          int        `json:"tenant_id"`
}

func (s *Subnet) MarshalJSON() ([]byte, error) {
	as := &apiSubnet{
		Name:              s.Name,
		Subnet:            s.Subnet.String(),
		ActiveStart:       s.ActiveStart.String(),
		ActiveEnd:         s.ActiveEnd.String(),
		ActiveLeaseTime:   int(s.ActiveLeaseTime.Seconds()),
		ReservedLeaseTime: int(s.ReservedLeaseTime.Seconds()),
		Options:           s.Options,
		Leases:            make([]*Lease, len(s.Leases)),
		Bindings:          make([]*Binding, len(s.Bindings)),
		TenantId:          s.TenantId,
	}
	if s.NextServer != nil {
		ns := s.NextServer.String()
		as.NextServer = &ns
	}
	i := int64(0)
	for _, lease := range s.Leases {
		as.Leases[i] = lease
		i++
	}
	i = int64(0)
	for _, binding := range s.Bindings {
		as.Bindings[i] = binding
		i++
	}
	return json.Marshal(as)
}

func (s *Subnet) UnmarshalJSON(data []byte) error {
	as := &apiSubnet{}
	if err := json.Unmarshal(data, &as); err != nil {
		return err
	}
	s.Name = as.Name
	_, netdata, err := net.ParseCIDR(as.Subnet)
	if err != nil {
		return err
	} else {
		s.Subnet = &MyIPNet{netdata}
	}
	s.ActiveStart = net.ParseIP(as.ActiveStart).To4()
	s.ActiveEnd = net.ParseIP(as.ActiveEnd).To4()

	if !netdata.Contains(s.ActiveStart) {
		return errors.New("ActiveStart not in Subnet")
	}
	if !netdata.Contains(s.ActiveEnd) {
		return errors.New("ActiveEnd not in Subnet")
	}

	s.ActiveLeaseTime = time.Duration(as.ActiveLeaseTime) * time.Second
	s.ReservedLeaseTime = time.Duration(as.ReservedLeaseTime) * time.Second
	if as.NextServer != nil {
		ip := net.ParseIP(*as.NextServer).To4()
		s.NextServer = &ip
	}
	if s.ActiveLeaseTime == 0 {
		s.ActiveLeaseTime = 300 * time.Second
	}
	if s.ReservedLeaseTime == 0 {
		s.ReservedLeaseTime = 2 * time.Hour
	}
	if s.Leases == nil {
		s.Leases = map[string]*Lease{}
	}

	for _, v := range as.Leases {
		s.Leases[v.Mac] = v
	}

	if s.Bindings == nil {
		s.Bindings = map[string]*Binding{}
	}

	for _, v := range as.Bindings {
		s.Bindings[v.Mac] = v
	}

	s.Options = as.Options
	s.TenantId = as.TenantId
	mask := net.IP([]byte(net.IP(netdata.Mask).To4()))
	bcastBits := binary.BigEndian.Uint32(netdata.IP) | ^binary.BigEndian.Uint32(mask)
	buf := make([]byte, 4)
	binary.BigEndian.PutUint32(buf, bcastBits)
	s.Options = append(s.Options, &Option{dhcp.OptionSubnetMask, mask.String()})
	s.Options = append(s.Options, &Option{dhcp.OptionBroadcastAddress, net.IP(buf).String()})
	return nil
}

func (subnet *Subnet) freeLease(dt *DataTracker, nic string) {
	lease := subnet.Leases[nic]
	if lease != nil {
		lease.ExpireTime = time.Now()
		dt.save_data(subnet.Name)
	}
}

func (s *Subnet) InRange(addr net.IP) bool {
	return bytes.Compare(addr, s.ActiveStart) >= 0 &&
		bytes.Compare(addr, s.ActiveEnd) <= 0
}

func (subnet *Subnet) findInfo(dt *DataTracker, nic string) (*Lease, *Binding) {
	l := subnet.Leases[nic]
	b := subnet.Bindings[nic]
	return l, b
}

// This will need to be updated to be more efficient with larger
// subnets.  Class C and below should be fine, however.
func (subnet *Subnet) getFreeIP() (*net.IP, bool) {
	activeLen := uint(dhcp.IPRange(subnet.ActiveStart, subnet.ActiveEnd))
	used := bitset.New(activeLen)
	saveMe := false
	for k, v := range subnet.Leases {
		if !subnet.InRange(v.Ip) {
			if _, found := subnet.Bindings[k]; found {
				// Lease is out of range, but we have a static binding for
				// it that matches.  Leave it alone.
				continue
			}
			if v.Valid {
				// Lease is out of range, and it does
				// not have a static binding.  Someone
				// changed our lease ranges out from
				// underneath us.  Mark the lease as
				// invalid so that it will get NAK'ed
				// the next time the client checks in.
				v.Valid = false
				saveMe = true
			}
			continue
		}
		if !v.Valid && !v.Phantom() {
			// The lease was marked invalid, but it is in
			// range and not a phantom lease.  Mark it as
			// valid again.
			v.Valid = true
			saveMe = true
		}
		bts := dhcp.IPRange(subnet.ActiveStart, v.Ip) - 1
		used = used.Set(uint(bts))
	}
	// Make sure that any static bindings in our range are masked out.
	for _, v := range subnet.Bindings {
		if subnet.InRange(v.Ip) {
			used = used.Set(uint(dhcp.IPRange(subnet.ActiveStart, v.Ip) - 1))
		}
	}
	bit, success := used.NextClear(0)
	if (success && bit < activeLen) || used.Len() == 0 {
		ip := dhcp.IPAdd(subnet.ActiveStart, int(bit))
		log.Printf("Handing out IP %v", ip)
		return &ip, true
	}
	// Didn't find an IP this way, find the most expired lease and use its IP.
	var target string
	for k, v := range subnet.Leases {
		// If the lease has expired, whack it.
		if _, ok := subnet.Bindings[k]; ok {
			continue
		}
		if !time.Now().After(v.ExpireTime) {
			continue
		}
		if target == "" || subnet.Leases[k].ExpireTime.After(subnet.Leases[target].ExpireTime) {
			ref := &rebar.Node{}
			ipNet := &net.IPNet{}
			ipNet.IP = v.Ip
			ipNet.Mask = subnet.Subnet.Mask
			toMatch := map[string]interface{}{"node-control-address": ipNet.String()}
			matches := []*rebar.Node{}
			err := rebarClient.Match(rebarClient.UrlPath(ref), toMatch, &matches)
			if err == nil && len(matches) > 0 {
				log.Printf("Expired lease for %s is being used by machine %s", k, matches[0].UUID)
				continue
			}
			target = k
		}
	}
	if target != "" {
		res := subnet.Leases[target].Ip
		delete(subnet.Leases, target)
		return &res, true
	}
	return nil, saveMe
}

func (subnet *Subnet) findOrGetInfo(dt *DataTracker, nic string, suggest net.IP) (*Lease, *Binding, bool) {
	binding := subnet.Bindings[nic]
	lease := subnet.Leases[nic]

	if binding == nil {
		fresh := false
		if lease == nil {
			// We have neither a lease nor a binding, create a lease.
			theip, saveMe := subnet.getFreeIP()
			if theip == nil {
				if saveMe {
					dt.save_data(subnet.Name)
				}
				return nil, nil, false
			}
			fresh = true
			lease = &Lease{
				Ip:         *theip,
				Mac:        nic,
				Valid:      true,
				State:      "PROBING",
				ExpireTime: time.Now().Add(subnet.ActiveLeaseTime),
			}
			subnet.Leases[nic] = lease
			dt.save_data(subnet.Name)
		}
		return lease, nil, fresh
	}

	if lease != nil && lease.Ip.Equal(binding.Ip) {
		return lease, binding, false
	}
	lease = &Lease{
		Ip:         binding.Ip,
		Mac:        nic,
		Valid:      true,
		ExpireTime: time.Now().Add(subnet.ReservedLeaseTime),
	}
	subnet.Leases[nic] = lease
	dt.save_data(subnet.Name)
	return lease, binding, false
}

func (s *Subnet) updateLeaseTime(dt *DataTracker, lease *Lease, d time.Duration, st string) {
	lease.ExpireTime = time.Now().Add(d)
	lease.State = st
	dt.save_data(s.Name)
}

func (s *Subnet) phantomLease(dt *DataTracker, nic string) {
	lease, _ := s.findInfo(dt, nic)
	if lease == nil {
		return
	}
	addr, err := net.ParseMAC(nic)
	if err != nil {
		return
	}
	// This is the MAC address range reserved for use in documentation.
	// We use it to ensure that we don't collide with real mac address ranges.
	ipBits := []byte(lease.Ip)
	addr[0] = 0x00
	addr[1] = 0x53
	addr[2] = ipBits[0]
	addr[3] = ipBits[1]
	addr[4] = ipBits[2]
	addr[5] = ipBits[3]
	lease.Valid = false
	lease.State = "DECLINE"
	lease.ExpireTime = time.Now().Add(10 * time.Minute)
	lease.Mac = addr.String()
	delete(s.Leases, nic)
	s.Leases[lease.Mac] = lease
	log.Printf("New phantom lease: %#v", lease)
	dt.save_data(s.Name)
}

func (s *Subnet) buildOptions(lease *Lease, binding *Binding, p dhcp.Packet) (dhcp.Options, time.Duration) {
	var lt time.Duration
	if binding == nil {
		lt = s.ActiveLeaseTime
	} else {
		lt = s.ReservedLeaseTime
	}

	opts := make(dhcp.Options)
	srcOpts := map[int]string{}
	for c, v := range p.ParseOptions() {
		srcOpts[int(c)] = convertByteToOptionValue(c, v)
		log.Printf("Recieved option: %v: %v", c, srcOpts[int(c)])
	}

	// Build renewal / rebinding time options
	b := make([]byte, 4)
	binary.BigEndian.PutUint32(b, uint32(lt/time.Second)/2)
	opts[dhcp.OptionRenewalTimeValue] = b
	b = make([]byte, 4)
	binary.BigEndian.PutUint32(b, uint32(lt/time.Second)*3/4)
	opts[dhcp.OptionRebindingTimeValue] = b

	// fold in subnet options
	for _, opt := range s.Options {
		c, v, err := opt.RenderToDHCP(srcOpts)
		if err != nil {
			log.Printf("Failed to render option %v: %v, %v\n", opt.Code, opt.Value, err)
			continue
		}
		opts[c] = v
	}

	// fold in binding options
	if binding != nil {
		for _, opt := range binding.Options {
			c, v, err := opt.RenderToDHCP(srcOpts)
			if err != nil {
				log.Printf("Failed to render option %v: %v, %v\n", opt.Code, opt.Value, err)
				continue
			}
			opts[c] = v
		}
	}

	return opts, lt
}
