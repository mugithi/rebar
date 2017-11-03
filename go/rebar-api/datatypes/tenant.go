package datatypes

type Tenant struct {
	SimpleID
	Name        string `json:"name"`
	Description string `json:"description"`
	ParentID    int64  `json:"parent_id"`
}

func (o *Tenant) ApiName() string {
	return "tenants"
}
