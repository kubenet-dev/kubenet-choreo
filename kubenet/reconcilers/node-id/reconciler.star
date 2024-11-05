load("core.network.kubenet.dev.networkdesigns.star", "get_network_design", "get_node_ipclaims", "get_node_asclaims")

def reconcile(self):
  # self = node
  partition = self.get("spec", {}).get("partition", "")
  namespace = self.get("spec", {}).get("namespace", "")
  network_design, err = get_network_design(partition, namespace)
  print("network_design", network_design)
  print("network_design", err)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)
  
  if is_conditionready(network_design, "IndexReady") != True:
      return reconcile_result(self, True, 0, "link ip claims not ready", False)
        
  ip_claims = get_node_ipclaims(network_design, self)
  print("ip_claims", ip_claims)
  for ip_claim in ip_claims:
    rsp = client_create(ip_claim)
    if rsp["error"] != None:
        return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  as_claims = get_node_asclaims(network_design, self)
  print("as_claims", as_claims)
  for as_claim in as_claims:
    rsp = client_create(as_claim)
    if rsp["error"] != None:
        return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  return reconcile_result(self, False, 0, "", False)