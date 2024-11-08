load("core.network.kubenet.dev.networkdesigns.star", "get_network_design")

def reconcile(self):
  # self = link
  if is_conditionready(self, "ClaimReady") != True:
    return reconcile_result(self, True, 0, "link ip claims not ready", False)

  network_design, err = get_network_design_link(self)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)
  
  interfaces, err = get_interfaces(self)
  if err != None:
    return reconcile_result(self, True, 0, err, False)
  for itfce in interfaces:
    rsp = client_create(itfce)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  subinterfaces, err = get_subinterfaces(self, network_design, interfaces)
  if err != None:
    return reconcile_result(self, True, 0, err, False)
  for si in subinterfaces:
    rsp = client_create(si)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  return reconcile_result(self, False, 0, "", False)

def get_network_design_link(link):
  namespace = link.get("metadata", {}).get("namespace", "")
  for endpoint in link.get("spec", {}).get("endpoints", []):
    partition = endpoint.get("partition", "")
    return get_network_design(partition, namespace)
  return None, "not found, no endpoints"

def get_interfaces(link):
  namespace = link.get("metadata", {}).get("namespace", "")
  interfaces = []
  for endpoint in link.get("spec", {}).get("endpoints", []):
    ep_name = get_endpoint_name(endpoint, "interface")
    ep = get_resource("infra.kuid.dev/v1alpha1", "Endpoint")
    rsp = client_get(ep_name, namespace, ep["resource"])
    if rsp["error"] != None:
      return None, rsp["error"]
    
    node = get_resource("infra.kuid.dev/v1alpha1", "Node")
    rsp = client_get(ep_name, namespace, ep["resource"])
    if rsp["error"] != None:
      return None, rsp["error"]
    node_spec = node.get("spec", {})
      
    interface = {
      "apiVersion": "device.network.kubenet.dev/v1alpha1",
      "kind": "Interface",
      "metadata": {
          "name": ep_name,
          "namespace": namespace,
      },
      "spec": {
        "partition": endpoint.get("partition", ""),
        "region": endpoint.get("region", ""),
        "site": endpoint.get("site", ""),
        "node": endpoint.get("node", ""),
        "provider": node_spec.get("provider", ""), # this comes from the node
        "platformType": node_spec.get("platformType", ""), # this comes from the node
        "port": int(endpoint.get("port", 0)),
        "adaptor": endpoint.get("adaptor", ""),
        "endpoint": int(endpoint.get("endpoint", 0)),
        "name": "interface",
        "vlanTagging": False,
        "mtu": 9000,
        "ethernet": {
          "speed": ep.get("spec", {}).get("speed") # this data is retrived from the ep
        }
      },
    }
    interfaces.append(interface)
  return interfaces, None

# returns ip info per endpoint of the link
def get_subinterfaces(link, network_design, interfaces):
  namespace = link.get("metadata", {}).get("namespace", "")
  subinterfaces = []

  # gather ep info
  link_endpoints = link.get("spec", {}).get("endpoints", [])
  eps = []
  for endpoint in link_endpoints:
    ep_info = {}
    ep_name = get_endpoint_name(endpoint, "interface")
    
    underlay = network_design.get("spec", {}).get("interfaces", {}).get("underlay", {})
    af = "ipv4"      
    if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == "ipv4numbered":
      # get ip_claim address
      address, err = get_ipclaim(".".join([ep_name, af]), namespace)
      if err != None:
        return None, err
      ep_info[af] = address

    af = "ipv6"      
    if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == "ipv6numbered":
      # get ip_claim address
      address, err = get_ipclaim(".".join([ep_name, af]), namespace)
      if err != None:
        return None, err
      ep_info[af] = address

    eps.append(ep_info)
  
  id = 0
  for endpoint in link_endpoints:
    ep_name = get_endpoint_name(endpoint, "interface")

    si = get_subinterface(ep_name, namespace, id, link_endpoints, eps, network_design, interfaces)
    subinterfaces.append(si)

    id += 1
  return subinterfaces, None


def get_subinterface(name, namespace, id, link_endpoints, eps_info, network_design, interfaces):
  local_addresses_ipv4, remote_addresses_ipv4 = get_addresses(id, eps_info, network_design, "ipv4", "ipv4numbered", "ipv4unnumbered")
  local_addresses_ipv6, remote_addresses_ipv6 = get_addresses(id, eps_info, network_design, "ipv6", "ipv6numbered", "ipv6unnumbered")
  
  local_endpoint = link_endpoints[id % 2]
  remote_endpoint = link_endpoints[(id + 1) % 2]

  interface = interfaces[id % 2]
  interface_spec = interface.get("spec", {})

  return {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "SubInterface",
    "metadata": {
        "name": name,
        "namespace": namespace,
    },
    "spec": {
      "partition": local_endpoint.get("partition", ""),
      "region": local_endpoint.get("region", ""),
      "site": local_endpoint.get("site", ""),
      "node": local_endpoint.get("node", ""),
      "provider": interface_spec.get("provider", ""), # this comes from the node
      "platformType": interface_spec.get("platformType", ""), # this comes from the node
      "port": int(local_endpoint.get("port", 0)),
      "adaptor": local_endpoint.get("adaptor", ""),
      "endpoint": int(local_endpoint.get("endpoint", 0)),
      "name": "interface",
      "id": id,
      "enabled": True,
      "type": "routed",
      "ipv4": local_addresses_ipv4,
      "ipv6": local_addresses_ipv6,
      "peer": {
        "partition": remote_endpoint.get("partition", ""),
        "region": remote_endpoint.get("region", ""),
        "site": remote_endpoint.get("site", ""),
        "node": remote_endpoint.get("node", ""),
        "port": int(remote_endpoint.get("port", 0)),
        "adaptor": remote_endpoint.get("adaptor", ""),
        "endpoint": int(remote_endpoint.get("endpoint", 0)),
        "name": "interface",
        "id": id,
        "ipv4": remote_addresses_ipv4,
        "ipv6": remote_addresses_ipv6,

      }
    },
  }

def get_addresses(id, ep_info, network_design, af, numbered, unnumbered):
  local = ep_info[id % 2]
  remote = ep_info[(id + 1) % 2]

  local_addresses = {"addresses": []}
  remote_addresses = {"addresses": []}

  underlay = network_design.get("spec", {}).get("interfaces", {}).get("underlay", {})

  if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == numbered:
    local_addresses["addresses"].append(local.get(af, ""))
    remote_addresses["addresses"].append(local.get(af, ""))
  elif underlay.get("addressing") == unnumbered:
    pass
  else:
    local_addresses = None
    remote_addresses = None
  return local_addresses, remote_addresses

def get_endpoint_name(endpoint, name):
  partition = endpoint.get("partition", "")
  region = endpoint.get("region", "")
  site = endpoint.get("site", "")
  node = endpoint.get("node", "")
  port = int(endpoint.get("port", 0))
  ep = int(endpoint.get("endpoint", 0))

  if name == "" or name == "interface":
    return ".".join([partition,region,site,node,str(port),str(ep)])
  return ".".join([partition,region,site,node,str(port),str(ep), name])

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