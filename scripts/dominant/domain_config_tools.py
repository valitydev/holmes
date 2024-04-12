#! /usr/bin/env python3

import json


def domain_make_version(version):
    result = {}
    if version == 'head':
        result = {"head": {}}
    else:
        result = {"version": int(version)}
    return result

def domain_get_object(obj_name, obj_ref, domain):
    for obj in domain:
        if obj_name in obj['key']:
            ref = obj.get("key").get(obj_name).get("id")
            if int(ref) == int(obj_ref):
                return obj.get("value").get(obj_name)

    return None

def domain_search_objects(obj_name, domain):
    obj_refs = []
    for obj in domain:
        if obj_name in obj['key']:
            ref = obj.get("key").get(obj_name).get("id")
            obj_refs.append(ref)

    return obj_refs

def selector_search_values(acc, selector):
    if "value" in selector:
        for val in selector.get("value"):
            val_id = val.get("id")
            acc.append(val_id)

    if "decisions" in selector:
        for d in selector.get("decisions"):
            if "then_" in d:
                decision_result = d.get("then_")
                if "value" in decision_result:
                    for val in decision_result.get("value"):
                        val_id = val.get("id")
                        if val_id not in acc:
                            acc.append(val_id)

                if "decisions" in decision_result:
                    deeper_decisions = decision_result.get("decisions")
                    deeper_values = selector_search_values([], deeper_decisions)
                    acc.extend(deeper_values)

    return acc
