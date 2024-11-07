load("core.network.kubenet.dev.networkdesigns.star", "get_network_design")

finalizer = "link.infra.kuid.dev/ids"
conditionType = "IPClaimReady"

def reconcile(self):
  # self is link
  network_design, err = get_network_design_link(self)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)
  
  if is_conditionready(network_design, "IndexReady") != True:
    return reconcile_result(self, True, 0, "index not ready", False)
        
  ip_claims = get_node_ipclaims(network_design, self)
  for ipclaim in ip_claims:
    rsp = client_create(ipclaim)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  return reconcile_result(self, False, 0, "", False)


def get_network_design_link(link):
  namespace = link.get("metadata", {}).get("namespace", "")
  for endpoint in link.get("spec", {}).get("endpoints", []):
    partition = endpoint.get("partition", "")
    return get_network_design(partition, namespace)
  return None, "not found, no endpoints"
  
def get_node_ipclaims(network_design, link):
  partition = network_design.get("metadata", {}).get("name", "")
  index = ".".join([partition, "default"])
  namespace = link.get("metadata", {}).get("namespace", "")
  link_name = link.get("metadata", {}).get("name", "")
  
  ip_claims = []
  underlay = network_design.get("spec", {}).get("interfaces", {}).get("underlay", {})

  af = "ipv4"      
  if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == "ipv4numbered":
    # link claim
    link_claim_name = ".".join([link_name, af])
    ip_claims.append(get_ipclaim_prefix(link_claim_name, namespace, index, af))

    # given the order is followed we now add the endpoint claims
    # as such the link get claimed and the ips within the link will follow
    for endpoint in link.get("spec", {}).get("endpoints", []):
      ep_name = get_endpoint_name(endpoint)
      ip_claims.append(get_ipclaim_address(".".join([ep_name, af]), namespace, index, af, link_claim_name))
  af = "ipv6"
  if underlay.get("addressing") == "dualstack" or underlay.get("addressing") == "ipv6numbered":
    # link claim
    link_claim_name = ".".join([link_name, af])
    ip_claims.append(get_ipclaim_prefix(link_claim_name, namespace, index, af))

    # given the order is followed we now add the endpoint claims
    # as such the link get claimed and the ips within the link will follow
    for endpoint in link.get("spec", {}).get("endpoints", []):
      ep_name = get_endpoint_name(endpoint)
      ip_claims.append(get_ipclaim_address(".".join([ep_name, af]), namespace, index, af, link_claim_name))
  
  return ip_claims

def get_ipclaim_prefix(name, namespace, index, af):
  prefixLength = 31
  if af == "ipv6":
    prefixLength = 64
  return {
    "apiVersion": "ipam.be.kuid.dev/v1alpha1",
    "kind": "IPClaim",
    "metadata": {
      "namespace": namespace,
      "name": name,
    },
    "spec": {
      "index": index,
      "prefixType": "network",
      "addressFamily": af,
      "prefixLength": prefixLength,
      "createPrefix": True,
      "selector": {
        "matchLabels": {
          "infra.kuid.dev/purpose": "underlay",
          "ipam.be.kuid.dev/address-family": af,
        },
      },
    },
  }

def get_ipclaim_address(name, namespace, index, af, link_name):
  return {
    "apiVersion": "ipam.be.kuid.dev/v1alpha1",
    "kind": "IPClaim",
    "metadata": {
      "namespace": namespace,
      "name": name,
    },
    "spec": {
      "index": index,
      "prefixType": "network",
      "selector": {
        "matchLabels": {
          "be.kuid.dev/claim-name": link_name,
          "ipam.be.kuid.dev/address-family": af,
        },
      },
    },
  }  

def get_endpoint_name(endpoint):
  partition = endpoint.get("partition", "")
  region = endpoint.get("region", "")
  site = endpoint.get("site", "")
  node = endpoint.get("node", "")
  port = int(endpoint.get("port", 0))
  ep = int(endpoint.get("endpoint", 0))

  return ".".join([
    partition,
    region,
    site,
    node,
    str(port),
    str(ep),
  ])

