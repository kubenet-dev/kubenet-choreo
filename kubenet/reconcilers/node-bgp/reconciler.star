load("core.network.kubenet.dev.networkdesigns.star", "get_network_design")

def reconcile(self):
  # self is node

  if is_conditionready(self, "ClaimReady") != True:
    return reconcile_result(self, True, 0, "node claims not ready", False)

  partition = self.get("spec", {}).get("partition", "")
  namespace = self.get("spec", {}).get("namespace", "")
  network_design, err = get_network_design(partition, namespace)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)

  protocols = network_design.get("spec", {}).get("protocols", {})
  if protocols.get("ibgp", None) != None or protocols.get("ebgp", None):
    rsp = client_create(get_bgp_dyn_neighbor(self))
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

    bgp, err = get_bgp(self, network_design)
    if err != None:
      return reconcile_result(self, True, 0, err, rsp["fatal"])
    rsp = client_create(bgp)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
    
  return reconcile_result(self, False, 0, "", False)

def get_bgp_dyn_neighbor(node):
  # update platform and platformType
  nodespec = node.get("spec", {})
  return {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "BGPDynamicNeighbor",
    "metadata": {
        "name": node.get("metadata", {}).get("name", ""),
        "namespace": node.get("metadata", {}).get("namespace", ""),
    },
    "spec": {
      "partition": nodespec.get("partition", ""),
      "region": nodespec.get("region", ""),
      "site": nodespec.get("site", ""),
      "node": nodespec.get("node", ""),
      "provider": nodespec.get("provider", ""),
      "platformType": nodespec.get("platformType", ""),
    },
  }
  
def get_bgp(node, network_design):
  nodespec = node.get("spec", {})
  asn, err = get_bgp_asn(node, network_design)
  if err != None:
    return None, err
  
  routerID, err = get_routerid(node, network_design)
  if err != None:
    return None, err
    
  nodespec = node.get("spec", {})
  return {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "BGP",
    "metadata": {
        "name": node.get("metadata", {}).get("name", ""),
        "namespace": node.get("metadata", {}).get("namespace", ""),
    },
    "spec": {
      "partition": nodespec.get("partition", ""),
      "region": nodespec.get("region", ""),
      "site": nodespec.get("site", ""),
      "node": nodespec.get("node", ""),
      "provider": nodespec.get("provider", ""),
      "platformType": nodespec.get("platformType", ""),
      "as": asn,
      "routerID": routerID,
      "addressFamilies": get_afs(network_design),
      "peerGroups": get_peer_groups(network_design),
    },
  }, None

def get_bgp_asn(node, network_design):
  partition = network_design.get("metadata", {}).get("name", "")
  namespace = node.get("metadata", {}).get("namespace", "")
  node_name = node.get("metadata", {}).get("name", "")

  # for ebgp the asclaim_name is the node name
  asclaim_name = partition + "." + "ibgp"
  if network_design.get("spec", {}).get("protocols", {}).get("ebgp", None) != None:
    asclaim_name = node_name
  
  return get_asclaim(asclaim_name, namespace)

def get_routerid(node, network_design):
  namespace = node.get("metadata", {}).get("namespace", "")
  node_name = node.get("metadata", {}).get("name", "")
  
  ipclaim_name = node_name + "." + "routerid"
  underlay = network_design.get("spec", {}).get("interfaces", {}).get("underlay", {})

  if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == "ipv4numbered":
    ipclaim_name = ".".join([node_name, "ipv4"])
  
  return get_ipclaim(ipclaim_name, namespace)

def get_asclaim(name, namespace):
  resource = get_resource("as.be.kuid.dev/v1alpha1", "ASClaim")
  rsp = client_get(name, namespace, resource["resource"])
  if rsp["error"] != None:
    return None, "ipclaim " + name + " err: " + rsp["error"]
  
  if is_conditionready(rsp["resource"], "Ready") != True:
    return None, "asclaim " + name + " not ready"
  return rsp["resource"].get("status", {}).get("id", 0), None

def get_ipclaim(name, namespace):
  resource = get_resource("ipam.be.kuid.dev/v1alpha1", "IPClaim")
  rsp = client_get(name, namespace, resource["resource"])
  if rsp["error"] != None:
    return None, "ipclaim " + name + " err: " + rsp["error"]
  
  if is_conditionready(rsp["resource"], "Ready") != True:
    return None, "ipclaim " + name + " not ready"
  address = rsp["resource"].get("status", {}).get("address", "")
  if address == "":
    return None, "ipclaim " + name + " no address in ip claim"
  return address, None



def get_underlay_afs(network_design):
  protocols = network_design.get("spec", {}).get("protocols", {})

  afs = []
  if network_design.get("spec", {}).get("protocols", {}).get("ebgp", None) != None:
    underlay = network_design.get("spec", {}).get("interfaces", {}).get("underlay", {})
    if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == "ipv4numbered" or underlay.get("addressing") == "ipv4unnumbered":
      afs.append({"name": "ipv4Unicast"})
    if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == "ipv6numbered" or underlay.get("addressing") == "ipv6unnumbered":
      afs.append({"name": "ipv6Unicast"})
  return afs
       

def get_overlay_afs(network_design):
  protocols = network_design.get("spec", {}).get("protocols", {})

  afs = []
  underlay = network_design.get("spec", {}).get("interfaces", {}).get("underlay", {})
  loopback = network_design.get("spec", {}).get("interfaces", {}).get("loopback", {})
  if (underlay.get("addressing") == "ipv6unnumbered" or underlay.get("addressing") == "ipv6numbered") and (loopback.get("addressing") == "dualstack" or loopback.get("addressing") == "ipv4numbered" or loopback.get("addressing") == "ipv4unnumbered"):
      afs.append({"name": "ipv4Unicast", "rfc5549": True})  
  # TBD do we need to add a case for underlay v4 only and v6 in overlay ??
  if protocols.get("bgpEVPN", None) != None:
      afs.append({"name": "bgpEVPN"})
  if protocols.get("bgpVPNv4", None) != None:
      afs.append({"name": "bgpVPNv4"})
  if protocols.get("bgpVPNv6", None) != None:
      afs.append({"name": "bgpVPNv6"})
  if protocols.get("bgpVPNv6", None) != None:
      afs.append({"name": "bgpVPNv6"})
  if protocols.get("bgpRouteTarget", None) != None:
      afs.append({"name": "bgpRouteTarget"})
  if protocols.get("bgpLabeledUnicastv4", None) != None:
      afs.append({"name": "bgpLabeledUnicastv4"})
  if protocols.get("bgpLabeledUnicastv6", None) != None:
      afs.append({"name": "bgpLabeledUnicastv6"})
  return afs

def get_afs(network_design):
  afs = get_underlay_afs(network_design)
  afs.extend(get_overlay_afs(network_design))
  return afs


def get_peer_groups(network_design):
  peer_groups = []
  if network_design.get("spec", {}).get("protocols", {}).get("ebgp", None) != None:
    peer_groups.append({"name": "underlay", "addressFamilies": get_underlay_afs(network_design)})
  peer_groups.append({"name": "overlay", "addressFamilies": get_overlay_afs(network_design)})
  return peer_groups 

