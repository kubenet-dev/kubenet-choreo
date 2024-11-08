load("core.network.kubenet.dev.networkdesigns.star", "get_network_design")

finalizer = "subinterface.kubenet.dev/bgpneighbor"
conditionType = "BGPNeighborReady"

def reconcile(self):
  si = self

  partition = self.get("spec", {}).get("partition", "")
  namespace = self.get("spec", {}).get("namespace", "")
  network_design, err = get_network_design(partition, namespace)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)
  
  bgp_neighbors, err = get_bgp_neighbors(si, network_design)
  if err != None:
    return reconcile_result(self, True, 0, err, False)
  for bgp_neighbor in bgp_neighbors:
    rsp = client_create(bgp_neighbor)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  return reconcile_result(self, False, 0, "", False)

def get_bgp_neighbors(si, network_design):
  # is ebgp enabled
  if network_design.get("spec", {}).get("protocols", {}).get("ebgp", None) == None:
    return [], None
  if si.get("spec", {}).get("name", "") == "interface":
    bgp_neighbors_ipv4, err = get_bgp_neighbors_per_af(si, "ipv4")
    if err:
      return None, err
    bgp_neighbors_ipv6, err = get_bgp_neighbors_per_af(si, "ipv6")
    if err:
      return None, err
    return bgp_neighbors_ipv4 + bgp_neighbors_ipv6, None
  return [], None
  
def get_bgp_neighbors_per_af(si, af):
  namespace = si.get("metadata", {}).get("namespace", "")
  si_name = si.get("metadata", {}).get("name", "")
  
  spec = si.get("spec", {})
  peer = spec.get("peer", {})
  local_node_name = ".".join([spec.get("partition", ""), spec.get("region", ""), spec.get("site", ""), spec.get("node", "")])
  peer_node_name = ".".join([peer.get("partition", ""), peer.get("region", ""), peer.get("site", ""), peer.get("node", "")])

  local_asn, err = get_asclaim(local_node_name, namespace)
  if err != None:
    return None, err

  peer_asn, err = get_asclaim(peer_node_name, namespace)
  if err != None:
    return None, err
  
  bgp_neighbors = []
  for idx, address in enumerate(si.get("spec", {}).get(af, {}).get("addresses", [])):
    local_address = address
    peer_address = si.get("spec", {}).get("peer", {}).get(af, {}).get("addresses", [])[idx]

    bgp_neighbor = {
      "apiVersion": "device.network.kubenet.dev/v1alpha1",
      "kind": "BGPNeighbor",
      "metadata": {
          "name": ".".join([si_name, af]),
          "namespace": namespace
      },
      "spec": {
        "partition": spec.get("partition", ""),
        "region": spec.get("region", ""),
        "site": spec.get("site", ""),
        "node": spec.get("node", ""),
        "provider": spec.get("provider", ""),
        "platformType": spec.get("platformType", ""),
        "localAddress": local_address,
        "localAS": local_asn,
        "peerAddress": peer_address,
        "peerAS": peer_asn,
        "peerGroup": "underlay",
      },
    }
    bgp_neighbors.append(bgp_neighbor)
  return bgp_neighbors, None

def get_asclaim(name, namespace):
  resource = get_resource("as.be.kuid.dev/v1alpha1", "ASClaim")
  rsp = client_get(name, namespace, resource["resource"])
  if rsp["error"] != None:
    return None, "ipclaim " + name + " err: " + rsp["error"]
  
  if is_conditionready(rsp["resource"], "Ready") != True:
    return None, "asclaim " + name + " not ready"
  return rsp["resource"].get("status", {}).get("id", 0), None