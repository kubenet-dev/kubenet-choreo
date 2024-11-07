def reconcile(self):
  ni = self 

  err = update_sub_interface(self)
  if err != None:
    return reconcile_result(self, True, 0, err, True)

  return reconcile_result(self, False, 0, "", False)

def update_sub_interface(ni):
  namespace = ni.get("metadata", {}).get("namespace", "")
  ni_name = ni.get("metadata", {}).get("name", "")
  spec = ni.get("spec", {})

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
      "id": int(si_spec.get("id", 0))
    }
    interfaces.append(interface)
  
  # Sort interfaces by multiple keys
  interfaces = insertion_sort(interfaces, lambda x: (x.get('id'), x.get('endpoint'), x.get('port'), x.get('name')))

  spec["interfaces"] = interfaces
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


