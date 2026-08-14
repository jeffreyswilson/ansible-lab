TF := terraform

HOURLY_TARGETS := \
	-target=aws_instance.test \
	-target=aws_nat_gateway.lab \
	-target=aws_eip.nat \
	-target=aws_ec2_transit_gateway_vpc_attachment.vpc1 \
	-target=aws_ec2_transit_gateway_vpc_attachment.vpc2

.PHONY: plan-pause pause plan-resume resume plan-full apply-full destroy-full state

plan-pause:
	$(TF) plan -destroy $(HOURLY_TARGETS)

pause:
	$(TF) destroy $(HOURLY_TARGETS)

plan-resume:
	$(TF) plan $(HOURLY_TARGETS)

resume:
	$(TF) apply $(HOURLY_TARGETS)

plan-full:
	$(TF) plan

apply-full:
	$(TF) apply

destroy-full:
	@echo "WARNING: this destroys every managed resource, structural included."
	@echo "Confirm this is intentional -- pause/resume should use 'make pause' instead."
	@read -p "Type 'destroy everything' to proceed: " confirm; \
	[ "$$confirm" = "destroy everything" ] || (echo "Aborted."; exit 1)
	$(TF) destroy

state:
	$(TF) state list
