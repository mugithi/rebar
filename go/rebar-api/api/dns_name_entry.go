package api

import "github.com/digitalrebar/digitalrebar/go/rebar-api/datatypes"

// DnsNameEntry wraps datatypes.DnsNameEntry to provide client API
// functionality
type DnsNameEntry struct {
	datatypes.DnsNameEntry
	Timestamps
	apiHelper
	rebarSrc
}

// DnsNameEntrys fetches all of the DnsNameEntrys in Rebar.
func (c *Client) DnsNameEntrys() (res []*DnsNameEntry, err error) {
	res = make([]*DnsNameEntry, 0)
	dne := &DnsNameEntry{}
	return res, c.List(c.UrlPath(dne), &res)
}
