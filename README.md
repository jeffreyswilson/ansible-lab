# Jeff's walk through Ansible

20 year veteran network engineer/architect taking an initial pass at
learning Ansible. Currently implemented on Ubuntu VMs manually created
within Parallels (one controller, two nodes), running on my MacBook Pro.
First tutorial was local filesystem only. As the lessons progress, this
README was born with the instantiation of `git` to capture project state
and progress.

## Project Shape

| Artifact | Description |
|---|---|
| README.md | This file |
| inventory.ini | Operational details for `control`, `node1`, and `node2` |
| templates/index.html.j2 | Initial pass at dynamic service configuration |
| playbooks/install_broken.yml | Intentional nerf to observe the effects of `command` vs `module` |
| playbooks/install.yml | Install `nginx` on nodes |
| playbooks/configure.yml | Custom HTML per node |
| group_vars/servers.yml | Capture server variables |
| ansible.cfg | Set reasonable project defaults |

## Project progress

See repo commit log.

## Git into the details

Directed acyclic graphs and least common ancestors - my prior experience
has been with CVS and SVN. The departure from this familiar base requires
some retooling of my imagination. My "lab" requires that I make a trivial
change to the repo to watch divergence and reconciliation in action. This
paragraph meets that trivial requirement.
