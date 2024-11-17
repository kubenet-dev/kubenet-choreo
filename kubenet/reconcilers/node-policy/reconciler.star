load("core.network.kubenet.dev.networkdesigns.star", "get_network_design")

def reconcile(self):
  #self = node
  partition = self.get("spec", {}).get("partition", "")
  namespace = self.get("metadata", {}).get("namespace", "")
  network_design, err = get_network_design(partition, namespace)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)

  rps = get_routing_policies(self, network_design)
  for rp in rps:
    rsp = client_create(rp)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  pss = get_prefix_sets(self, network_design)
  for ps in pss:
    rsp = client_create(ps)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  return reconcile_result(self, False, 0, "", False)

def get_routing_policies(node, network_design):
  rps = []
  rps.append(get_underlay_routing_policies(node, network_design))
  rps.append(get_overlay_routing_policies(node, network_design))
  return rps

def get_underlay_routing_policies(node, network_design):
  statements = []
  if network_design.get("spec", {}).get("protocols", {}).get("ebgp", None) != None:
    ipv4_loopback_prefixes = get_prefixes(network_design, "loopback", "ipv4")
    if len(ipv4_loopback_prefixes) > 0:
      statements.append({"id": 10, "match": get_routing_policy_metch("loopbackIPv4"), "action": {"result": "accept"}})
    ipv6_loopback_prefixes = get_prefixes(network_design, "loopback", "ipv6")
    if len(ipv6_loopback_prefixes) > 0:
      statements.append({"id": 20, "match": get_routing_policy_metch("loopbackIPv6"), "action": {"result": "accept"}})
  return get_routing_policy(node, "underlay", statements)

def get_overlay_routing_policies(node, network_design):
  return get_routing_policy(node, "overlay", [])
   

def get_routing_policy_metch(prefixset_ref = None, tagset_ref = None, family = None, protocol = None, bgp = None, isis = None, ospf = None):
  match = {}
  if prefixset_ref != None:
    match["prefixSetRef"] = prefixset_ref
  if tagset_ref != None:
    match["tagSetRef"] = tagset_ref
  if family != None:
    match["family"] = family
  if protocol != None:
    match["protocol"] = protocol
  if bgp != None:
    match["bgp"] = bgp
  if ospf != None:
    match["ospf"] = ospf
  if isis != None:
    match["isis"] = isis
  return match
  

def get_routing_policy(node, policy_name, statements = [], defaultAction = None):
  node_name = node.get("metadata", {}).get("name", "")
  namespace = node.get("metadata", {}).get("namespace", "")

  if defaultAction == None:
    defaultAction = {"result": "reject"}

  # update platform and platformType

  node_spec = node.get("spec", {})
  policy = {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "RoutingPolicy",
    "metadata": {
      "name": ".".join([node_name,  policy_name.lower()]),
      "namespace": namespace,
    },
    "spec": {
      "partition": node_spec.get("partition", ""),
      "region": node_spec.get("region", ""),
      "site": node_spec.get("site", ""),
      "node": node_spec.get("node", ""),
      "provider": node_spec.get("provider", ""),
      "platformType": node_spec.get("platformType", ""),
      "name": policy_name.lower(),
      "defaultAction": defaultAction,
    },
  }
  if statements:
    policy["spec"]["statements"] = statements
  return policy

def get_prefix_sets(node, network_design):
  prefix_sets = []
  if network_design.get("spec", {}).get("protocols", {}).get("ebgp", None) != None:
    ipv4_loopback_prefixes = get_prefixes(network_design, "loopback", "ipv4")
    if len(ipv4_loopback_prefixes) > 0:
      prefixes = []
      for prefix in ipv4_loopback_prefixes:
        prefixes.append({"prefix": prefix, "maskLengthRange": "32..32"})
      prefix_sets.append(get_prefix_set(node, "loopbackIPv4", prefixes))

    ipv6_loopback_prefixes = get_prefixes(network_design, "loopback", "ipv6")
    if len(ipv6_loopback_prefixes) > 0:
      prefixes = []
      for prefix in ipv6_loopback_prefixes:
        prefixes.append({"prefix": prefix, "maskLengthRange": "128..128"})
      prefix_sets.append(get_prefix_set(node, "loopbackIPv6", prefixes))
  return prefix_sets

def get_prefixes(network_design, prefix_type, af):
  prefixes = network_design.get("spec", {}).get("interfaces", {}).get(prefix_type, {}).get("prefixes", [])
  af_prefixes = []
  for prefix in prefixes:
    p = prefix.get("prefix", "")
    if af == "ipv4" and is_ipv4(p):
      af_prefixes.append(p)
    if af == "ipv6" and is_ipv6(p):
      af_prefixes.append(p)
  return af_prefixes


def get_prefix_set(node, name, prefixes):
  node_name = node.get("metadata", {}).get("name", "")
  namespace = node.get("metadata", {}).get("namespace", "")

  node_spec = node.get("spec", {})
  return {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "PrefixSet",
    "metadata": {
        "name": ".".join([node_name, name.lower()]),
        "namespace": namespace,
    },
    "spec": {
      "partition": node_spec.get("partition", ""),
      "region": node_spec.get("region", ""),
      "site": node_spec.get("site", ""),
      "node": node_spec.get("node", ""),
      "provider": node_spec.get("provider", ""),
      "platformType": node_spec.get("platformType", ""),
      "name": name.lower(),
      "prefixes": prefixes,
    },
  }