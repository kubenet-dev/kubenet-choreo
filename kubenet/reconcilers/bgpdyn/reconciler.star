load("core.network.kubenet.dev.networkdesigns.star", "get_network_design")

def reconcile(self):
  # self is dynBGPNeighbor
  dyn_bgp_neighbor = self

  # this should work for create/update and delete
  partition = self.get("spec", {}).get("partition", "")
  namespace = self.get("spec", {}).get("namespace", "")
  network_design, err = get_network_design(partition, namespace)
  if err != None:
    # we dont return the error but wait for the network design retrigger
    return reconcile_result(self, False, 0, err, False)

  err = update_sub_interface(self, network_design)
  if err != None:
    return reconcile_result(self, True, 0, err, True)
    
  return reconcile_result(self, False, 0, "", False)  

def update_sub_interface(dyn_bgp_neighbor, network_design):
  spec = dyn_bgp_neighbor.get("spec", {})
  addressing = network_design.get("spec", {}).get("interfaces", {}).get("underlay", {}).get("addressing", "")
  if not (addressing == "ipv4unnumbered" or addressing == "ipv6unnumbered"):
    spec.pop("interfaces", None)
    return None

  fieldSelector = {}
  fieldSelector["spec.partition"] = spec.get("partition", "")
  fieldSelector["spec.region"] = spec.get("region", "")
  fieldSelector["spec.site"] = spec.get("site", "")
  fieldSelector["spec.node"] = spec.get("node", "")

  silist = get_resource("device.network.kubenet.dev/v1alpha1", "SubInterface")
  rsp = client_list(silist["resource"], fieldSelector)
  if rsp["error"] != None:
    return rsp["error"]
  
  interfaces = []
  items = rsp["resource"].get("items", [])
  for si in items:
    si_spec = si.get("spec")
    interface = {
      "partition": si_spec.get("partition", ""),
      "region": si_spec.get("region", ""),
      "site": si_spec.get("site", ""),
      "node": si_spec.get("node", ""),
      "port": int(si_spec.get("port", 0)),
      "endpoint": int(si_spec.get("endpoint", 0)),
      "name": si_spec.get("name", ""),
      "id": int(si_spec.get("id", 0)),
      "peerAS": 0,
      "peerGroup": "underlay",
    }
    interfaces.append(interface)
  
  # Sort interfaces by multiple keys
  interfaces = insertion_sort(interfaces, lambda x: (x.get('id'), x.get('endpoint'), x.get('port'), x.get('name')))

  spec["interfaces"] = interfaces
  if len(interfaces) == 0:
    spec.pop("interfaces", None) 
    

  return None

def insertion_sort(arr, key_func):
  for i in range(1, len(arr)):
    key_item = arr[i]
    key_value = key_func(key_item)
    # Insert key_item into the sorted sequence arr[0 ... i-1]
    inserted = False
    for j in range(i - 1, -1, -1):
      if key_func(arr[j]) > key_value:
        arr[j + 1] = arr[j]
      else:
        arr[j + 1] = key_item
        inserted = True
        break
    if not inserted:
      arr[0] = key_item
  return arr