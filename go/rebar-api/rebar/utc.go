package main

import "github.com/digitalrebar/digitalrebar/go/rebar-api/api"

func init() {
	app.AddCommand(makeCommandTree("user_tenant_capability",
		func() api.Crudder { return &api.UserTenantCapability{} },
	))
}
