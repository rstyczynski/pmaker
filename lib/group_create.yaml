---
- hosts: all
  
  tasks:
  - name: groups
    include_vars: 
      file: ../cfg/groups.yaml
  - name: declare group
    debug:
      msg: "group name: {{ item.key }} with gid: {{ item.value }}"
    with_dict: "{{ groups_dict }}"

  - name: Create group with gid (to have the same gid on all nodes to be able to use nfs)
    become: yes
    group:
      name: "{{ item.key }}"
      gid: "{{ item.value }}"
      state: present
    with_dict: "{{ groups_dict }}"