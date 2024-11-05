load("core.network.kubenet.dev.networkdesigns.star", "get_node_ipclaims", "get_node_asclaims")

def reconcile(self):
  # self = node
  partition = self.get("spec", {}).get("partition", "")
  namespace = self.get("spec", {}).get("namespace", "")
  network_design, err = get_network_design(partition, namespace)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)
        
  ip_claims = get_node_ipclaims(network_design, self)
  for ip_claim in ip_claims:
    rsp = client_create(ip_claim)
    if rsp["error"] != None:
        return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  as_claims = get_node_asclaims(network_design, self)
  for as_claim in as_claims:
    rsp = client_create(as_claim)
    if rsp["error"] != None:
        return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  return reconcile_result(self, False, 0, "", False)