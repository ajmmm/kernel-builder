VM ?= ./build_vm.sh

.PHONY: image seed create boot down destroy status ssh up

image:
	$(VM) image

seed:
	$(VM) seed

create:
	$(VM) create

boot:
	$(VM) boot

down:
	$(VM) down

destroy:
	$(VM) destroy

status:
	$(VM) status

ssh:
	$(VM) ssh-config

up:
	$(VM) up
