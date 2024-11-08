load("core.network.kubenet.dev.networkdesigns.star", "get_network_design")


def reconcile(self):
  #self = node
  node = self
  if is_conditionready(self, "ClaimReady") != True:
    return reconcile_result(self, True, 0, "node claim not ready", False)

  partition = node.get("spec", {}).get("partition", "")
  namespace = node.get("spec", {}).get("namespace", "")
  network_design, err = get_network_design(partition, namespace)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)

  for itfce in get_node_interfaces(self):
    rsp = client_create(itfce)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  subinterface, err = get_node_subinterface(self, network_design)
  if err != None:
    return reconcile_result(self, True, 0, err, False)
  rsp = client_create(subinterface)
  if rsp["error"] != None:
    return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  rsp = client_create(get_network_instance(self))
  if rsp["error"] != None:
    return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"]) 
  
  return reconcile_result(self, False, 0, "", False)


def get_node_interfaces(node):
  namespace = node.get("metadata", {}).get("namespace", "")
  node_spec = node.get("spec", {})
  partition = node_spec.get("partition", "")
  region = node_spec.get("region", "")
  site = node_spec.get("site", "")
  node_name = node_spec.get("node", "")

  # update platform and platformType

  interfaces = []
  for ifname in ["system", "irb"]:
    interface = {
      "apiVersion": "device.network.kubenet.dev/v1alpha1",
      "kind": "Interface",
      "metadata": {
          "name": ".".join([partition, region, site, node_name, str(0), str(0), ifname]),
          "namespace": namespace,
      },
      "spec": {
        "partition": partition,
        "region": region,
        "site": site,
        "node": node_name,
        "port": 0,
        "endpoint": 0,
        "name": ifname,
        "vlanTagging": False,
        "mtu": 9000,
      },
    }
    interfaces.append(interface)
  return interfaces

def get_node_subinterface(node, network_design):
  namespace = node.get("metadata", {}).get("namespace", "")
  node_spec = node.get("spec", {})
  partition = node_spec.get("partition", "")
  region = node_spec.get("region", "")
  site = node_spec.get("site", "")
  node_name = node_spec.get("node", "")


  addresses_ipv4, err = get_node_addresses(node, network_design, "ipv4", "ipv4numbered")
  if err != None:
    return None, err
  addresses_ipv6, err = get_node_addresses(node, network_design, "ipv6", "ipv6numbered")
  if err != None:
    return None, err
  
  return {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "SubInterface",
    "metadata": {
        "name": ".".join([partition, region, site, node_name, str(0), str(0), "system", str(0)]),
        "namespace": namespace,
    },
    "spec": {
      "partition": partition,
      "region": region,
      "site": site,
      "node": node_name,
      "port": 0,
      "endpoint": 0,
      "name": "system",
      "id": 0,
      "enabled": True,
      "type": "routed",
      "ipv4": addresses_ipv4,
      "ipv6": addresses_ipv6,
    },
  }, None

def get_network_instance(node):
  namespace = node.get("metadata", {}).get("namespace", "")
  node_name = node.get("metadata", {}).get("name", "")
  node_spec = node.get("spec", {})

  return {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "NetworkInstance",
    "metadata": {
      "name": ".".join([node_name, "default"]),
      "namespace": namespace,
    },
    "spec": {
      "partition": node_spec.get("partition", ""),
      "region": node_spec.get("region", ""),
      "site": node_spec.get("site", ""),
      "node": node_spec.get("node", ""),
      "provider": node_spec.get("provider", ""),
      "platformType": node_spec.get("platformType", ""),
      "name": "default",
      "id": 0,
      "type": "default",
    },
  }
  

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


def get_node_addresses(node, network_design, af, numbered):
  node_name = node.get("metadata", {}).get("name", "")
  namespace = node.get("metadata", {}).get("namespace", "")
  
  addresses = None
  # if af is enabled
  loopback = network_design.get("spec", {}).get("interfaces", {}).get("loopback", {})
  if loopback.get("addressing") == "dualstack" or loopback.get("addressing") == numbered:
    address, err = get_ipclaim(".".join([node_name, af]), namespace) 
    if err != None:
      return None, err
    addresses = {"addresses": [address]}
    
  return addresses, None

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